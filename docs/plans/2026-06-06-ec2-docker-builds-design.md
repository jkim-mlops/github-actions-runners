# Design: Docker (DinD) Builds on ECS Managed Instances

**Date:** 2026-06-06
**Branch:** `feat/ec2-docker-builds`
**Status:** Approved design — ready for implementation planning

## Problem

Self-hosted GitHub Actions runners currently run on **ECS Fargate**. Fargate cannot
run real `docker build`: it has no privileged mode / Docker-in-Docker, so the runner
image works around this with rootless `buildah` + `fuse-overlayfs` (with `SYS_ADMIN`
capabilities added). We want CI jobs to run genuine `docker build`.

## Solution overview

Add a parallel, Docker-capable runner path on an **ECS Managed Instances (MI)**
capacity provider, running **rootful Docker-in-Docker** (`privileged: true`). Keep the
existing Fargate conda runner untouched. The webhook Lambda routes each `workflow_job`
by its requested `runs-on` labels:

- `runs-on: [self-hosted]` → existing **Fargate** task (unchanged)
- `runs-on: [self-hosted, docker]` → new **DinD** task on the **MI capacity provider**

Both paths stay **ephemeral and scale-to-zero**.

### Why Managed Instances (decisions captured)

- **Hybrid, not replace** — keep Fargate for normal jobs; only Docker-build jobs need EC2-class compute.
- **DinD, not host `docker.sock`** — MI deliberately removes host access (immutable
  root filesystem, SELinux, no SSH, no admin), so the host socket cannot be mounted.
  In-task DinD is also the *more secure* pattern (host-socket mount = root on the host).
- **Rootful DinD with `privileged: true`** — most compatible / fastest to working
  builds. SELinux + the immutable, disposable, auto-recycled host contain the blast
  radius. Rootless dockerd/BuildKit is a documented hardening follow-up.
- **MI over self-managed EC2 ASG** — chosen for security posture: AWS-managed instances,
  immutable rootfs, SELinux, automatic security patching, ≤14-day instance lifetime,
  scale-to-zero with no `min_size` to manage. The `ecs` module already has an ASG
  capacity provider that would also support DinD with less work, but MI's security/ops
  story won.

### How privileged enables DinD

The in-task `dockerd` needs `CAP_SYS_ADMIN` (mount/`pivot_root`, new mount namespaces
for the overlay2 storage driver and child containers) and `CAP_NET_ADMIN` (bridge,
veth, iptables NAT). Capabilities alone are often insufficient for *rootful* DinD —
the default seccomp profile and AppArmor/SELinux policy block `mount` regardless of
capability, and device-cgroup restrictions block device access. `privileged: true`
bundles the device access + seccomp/LSM relaxation that classic `docker:dind` expects.
On MI this is **two-layer gated**: opt in to privileged Linux capabilities at the
**capacity-provider** level, *then* set `privileged`/capabilities in the task def.
SELinux remains enforced even for privileged containers.

### Scale-to-zero & future warm-pooling

MI scales to zero automatically — idle instances with no running tasks are terminated
("you only pay for active resources"); ECS provisions on demand when a task is placed.
First job after idle pays a cold-start (instance launch + image pull).

**Future warm-pooling** will use MI's **configurable scale-in delay** (keeps an instance
*running*, not stopped, briefly after a task) — NOT EC2 Auto Scaling warm pools. The
previously-used EventBridge → SSM → "restart the ECS agent on stopped warm-pool
instances" runbook does **not** apply to MI: there is no customer-owned ASG / warm pool,
and MI prohibits host-level SSM/SSH access (AWS owns the ECS-agent lifecycle). The
agent-restart failure mode that runbook fixed therefore does not exist on MI.

## Components & two-repo split

### Repo A — `terraform-modules` (`modules/ecs`)

The module already supports FARGATE and an ASG-based EC2 capacity provider. Add a
Managed Instances capacity-provider capability alongside them:

- `aws_ecs_capacity_provider` with a `managed_instances_provider` block:
  `infrastructure_role_arn`, `instance_launch_template` (instance profile + network
  config), instance requirements/types, storage configuration.
- New IAM **infrastructure role** (lets ECS launch/terminate/manage instances) and the
  task **instance profile**.
- The **privileged-capability opt-in** on the capacity provider.
- Support `requiresCompatibilities = ["MANAGED_INSTANCES"]` task definitions and
  `privileged: true` / `linuxParameters.capabilities` on container definitions.
- Tag for a new release (e.g. `0.5.0`); consumed downstream via `?ref=`.
- **TF issue #44783:** `aws_ecs_cluster_capacity_providers` cannot manage ASG and MI
  providers together — register the MI provider on its own.
- Verified: the pinned AWS provider `~> 6.27.0` supports `managed_instances_provider`.

### Repo B — `github-actions-runners`

- **`images/dind/`** — new image: GitHub runner agent + `dockerd` (rootful DinD).
  Starts `dockerd` in the entrypoint/wrapper before the runner registers; runner
  registers with labels `self-hosted,docker`. Storage driver `overlay2`. Ephemeral,
  dies with the task. (Open: fork vs. extend the existing conda/buildah base.)
- **Second `ecs` task definition** for the DinD runner: `privileged: true`,
  `requiresCompatibilities = ["MANAGED_INSTANCES"]`, writable scratch on a `/var`-class
  path (MI's root filesystem is read-only).
- **Lambda webhook** routing changes (see below).
- **`images/runner/setup-runner.py`** — pass `--labels` (base + unique token) to
  `config.sh`; make `runner_name` stable. Applies to both runner images.
- Wire the MI capacity provider through `main.tf` and `variables.tf`.

## Data flow (webhook routing change)

`images/webhook/lambda.py` currently hardcodes `launchType="FARGATE"` and a single task
ARN, and only reads repo owner/name from the payload. New logic:

1. Parse `body["workflow_job"]["labels"]` (the requested `runs-on` labels) — new field.
2. If labels contain `docker` → `run_task` with
   `capacityProviderStrategy=[{"capacityProvider": <MI-CP>}]` targeting the **DinD task ARN**.
3. Else → existing `launchType="FARGATE"` path (unchanged).
4. Set `containerOverrides[].name` to **match the target task def's container name**
   (fargate-runner vs dind-runner). This is a *selector* and must match the task def
   exactly — it cannot be a unique-per-run value. So the Lambda must carry both
   container names and pick the right one per launch.
5. New env vars: `DOCKER_RUNNER_TASK_ARN`, `DOCKER_RUNNER_TASK_NAME`, `MI_CAPACITY_PROVIDER`.
6. Existing `queued`/`completed` action handling (including rerun support) preserved.

> Note: `run_task` for MI uses `capacityProviderStrategy`, not `launchType`.

## Runner label uniqueness (bug fix — applies to both paths)

**Symptom:** Queued jobs intermittently are not picked up even though idle runners are
online. Observed with multiple ephemeral runners that share an **identical label set**
(`self-hosted`, `Linux`, `ARM64`). Runner *names* are already unique (UUID suffix);
the **labels** are not.

**Root cause:** A known GitHub-side issue (community discussion
[#120813](https://github.com/orgs/community/discussions/120813)) — when several idle
ephemeral runners advertise identical labels, GitHub's matcher can get into a state
where it stops dispatching queued jobs to some of them. No official fix; the community
workaround is to make each runner's label set distinct.

**Why a unique label is safe for routing:** GitHub dispatches a job to a runner when the
job's `runs-on` set is a **subset** of the runner's labels. A runner advertising
`[self-hosted, arm64, docker, <unique>]` still matches a job requesting
`[self-hosted, docker]`; the extra unique label does not affect matching, it only keeps
the matcher out of the stuck-idle state.

**Fix:**
1. The Lambda generates a unique token per launch (reuse the runner-name hash, or derive
   from `workflow_job.run_id`) and passes it as an env override (e.g. `RUNNER_LABELS`).
2. `setup-runner.py` passes `--labels` to `config.sh` (it currently passes none):
   base labels + `docker` (DinD path only) + the unique token.
3. Also fix the latent footgun in `setup-runner.py`: `runner_name` is a `@computed_field`
   that mints a fresh UUID on every access — make it stable (compute once) so name and
   label tokens are consistent.

This fix is independent of DinD and improves the existing Fargate path too.

## Error handling

- **Cold start:** first DinD job after idle waits on MI instance provisioning + image
  pull. Optionally soften later with scale-in delay.
- **dockerd startup:** task entrypoint fails fast if `dockerd` does not become ready, so
  the job errors clearly instead of hanging.
- **Unknown labels:** Lambda logs and falls back rather than crashing.

## Security

- Privileged is gated twice (capacity-provider opt-in + task flag).
- Blast radius contained by SELinux + immutable, disposable, auto-recycled host.
- Runner stays ephemeral / single-job.
- Rootless dockerd/BuildKit recorded as a hardening follow-up.

## Testing

- `terraform validate` / `plan` in both repos.
- Smoke-test workflow: `runs-on: [self-hosted, docker]` running an actual `docker build`
  end-to-end.
- Confirm the instance drains and the cluster returns to zero after the job.

## Open risks to resolve during planning

- Exact Terraform argument name for the MI privileged-capability opt-in.
- Architecture choice for MI (arm64 vs x86_64) and matching runner download.
- Fork the DinD runner image or extend the existing conda/buildah base.
