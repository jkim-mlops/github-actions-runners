# Docker (DinD) Builds on ECS Managed Instances — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let GitHub Actions CI jobs run real `docker build` by routing `docker`-labeled jobs to an ephemeral, privileged Docker-in-Docker runner on an ECS Managed Instances capacity provider, while normal jobs keep using Fargate.

**Architecture:** Hybrid. The webhook Lambda inspects each `workflow_job`'s `runs-on` labels: `docker` → new DinD task on the Managed Instances (MI) capacity provider (`capacityProviderStrategy`, `privileged: true`); otherwise the existing Fargate task (`launchType=FARGATE`). The DinD image is built `FROM` the existing runner image (single source of truth for `setup-runner.py`) and starts its own `dockerd`. A separate, cross-cutting fix gives every ephemeral runner a unique label to dodge a known GitHub matcher bug (community #120813).

**Tech Stack:** Terraform (AWS provider `~> 6.27`), the private `terraform-modules` repo (`modules/ecs`, `modules/docker`), Python 3.13 AWS Lambda (aws-lambda-powertools, pydantic-settings, boto3), Docker/DinD, conda for tooling.

**Design doc:** `docs/plans/2026-06-06-ec2-docker-builds-design.md`

**Two repos:**
- **A** = `/Users/jkim/projects/terraform-modules` (shared modules — versioned, consumed via `?ref=`)
- **B** = `/Users/jkim/projects/github-actions-runners` (this repo)

**General notes for the executor:**
- Terraform isn't unit-testable like code; "verify" steps use `terraform fmt -check`, `terraform validate`, and `terraform plan`. The Lambda/Python logic IS unit-tested with `pytest`.
- Commit after every green step. Use the repo's emoji-prefixed conventional-commit style (e.g. `feat(lambda.py): :sparkles: ...`).
- Several AWS Managed Instances argument names are new; Task 1.3 verifies them against the live provider schema rather than trusting this plan.
- Use the `tidy` skill (terraform fmt + terraform-docs) before committing Terraform changes.

---

## Phase 1 — `terraform-modules`: Managed Instances support

> All work in repo **A**. Branch: `git -C /Users/jkim/projects/terraform-modules checkout -b feat/managed-instances`.

### Task 1.1: Add `build_args` to the `docker` module

**Why:** The DinD image must build `FROM` the runner image (dynamic ECR URL), so the build needs an injected `BASE_IMAGE` arg. Keeps `setup-runner.py` a single source of truth.

**Files:**
- Modify: `modules/docker/variables.tf`
- Modify: `modules/docker/main.tf:35-45`

**Step 1: Add the variable**

In `modules/docker/variables.tf`:
```hcl
variable "build_args" {
  description = "Build-time ARGs passed to the docker build."
  type        = map(string)
  default     = {}
}
```

**Step 2: Wire it into the build block**

In `modules/docker/main.tf`, inside `resource "docker_image" "this"` `build {}`:
```hcl
  build {
    context   = var.build_context
    tag       = ["${aws_ecr_repository.this.repository_url}:${var.image_tag}"]
    platform  = var.platform
    build_args = var.build_args
  }
```

**Step 3: Verify**

Run: `cd /Users/jkim/projects/terraform-modules && terraform -chdir=modules/docker init -backend=false && terraform -chdir=modules/docker validate`
Expected: `Success! The configuration is valid.`

**Step 4: Commit**
```bash
git -C /Users/jkim/projects/terraform-modules add modules/docker
git -C /Users/jkim/projects/terraform-modules commit -m "feat(docker): :sparkles: support build_args"
```

---

### Task 1.2: Add Managed Instances variables to the `ecs` module

**Files:**
- Modify: `modules/ecs/variables.tf`

**Step 1: Add variables**
```hcl
variable "enable_managed_instances" {
  description = "Create an ECS Managed Instances capacity provider alongside the existing providers."
  type        = bool
  default     = false
}

variable "managed_instances_instance_requirements" {
  description = "Attribute-based instance selection for Managed Instances (vCPU/memory ranges, etc.)."
  type        = any
  default     = null
}

variable "managed_instances_allow_privileged" {
  description = "Opt in to privileged Linux capabilities (CAP_SYS_ADMIN etc.) on the MI capacity provider. Required for Docker-in-Docker."
  type        = bool
  default     = false
}
```

**Step 2: Verify** — `terraform -chdir=modules/ecs validate` (after init `-backend=false`). Expected: valid.

**Step 3: Commit** — `feat(ecs): :sparkles: add managed instances variables`

---

### Task 1.3: VERIFY exact MI provider schema, then add the infrastructure role + capacity provider

**Why first verify:** Managed Instances arguments (`managed_instances_provider`, `infrastructure_role_arn`, `instance_launch_template`, the privileged-capability opt-in field) are new. Confirm names against the installed provider before writing HCL.

**Step 1: Dump the schema**

Run:
```bash
cd /Users/jkim/projects/terraform-modules/modules/ecs
terraform init -backend=false
terraform providers schema -json | python -m json.tool | grep -iA40 "managed_instances_provider"
```
Expected: the block's argument names, including the field that enables privileged capabilities. **Use the names you see, not the placeholders below.**

**Files:**
- Modify: `modules/ecs/main.tf`

**Step 2: Add the infrastructure IAM role** (lets ECS manage instances on your behalf)
```hcl
data "aws_iam_policy_document" "mi_infra_assume" {
  count = var.enable_managed_instances ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mi_infrastructure" {
  count              = var.enable_managed_instances ? 1 : 0
  name               = "${var.name}-ecs-mi-infra"
  assume_role_policy = data.aws_iam_policy_document.mi_infra_assume[0].json
}

resource "aws_iam_role_policy_attachment" "mi_infrastructure" {
  count      = var.enable_managed_instances ? 1 : 0
  role       = aws_iam_role.mi_infrastructure[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForManagedInstances"
}
```
> Verify the managed-policy ARN exists in Step 1's schema era; if not, attach an inline policy granting `ec2:RunInstances/TerminateInstances/CreateTags`, `iam:PassRole`, etc. per the MI infrastructure-role docs.

**Step 3: Add the capacity provider** (use verified arg names)
```hcl
resource "aws_ecs_capacity_provider" "managed_instances" {
  count = var.enable_managed_instances ? 1 : 0
  name  = "${var.name}-mi"

  managed_instances_provider {
    infrastructure_role_arn = aws_iam_role.mi_infrastructure[0].arn
    # propagate_tags = "CAPACITY_PROVIDER"

    instance_launch_template {
      ec2_instance_profile_arn = aws_iam_instance_profile.instance.arn
      network_configuration {
        subnets         = var.subnet_ids
        security_groups = length(var.security_group_ids) == 0 ? [aws_security_group.this.id] : var.security_group_ids
      }
      # instance_requirements / storage_configuration as needed
    }

    # PRIVILEGED OPT-IN: set the field name confirmed in Step 1 (gates CAP_SYS_ADMIN etc.)
    # e.g. propagate the var.managed_instances_allow_privileged flag here.
  }
}
```
> The instance profile `aws_iam_instance_profile.instance` already exists in this module (used by the ASG path) — reuse it.

**Step 4: Register the MI provider on its own** (TF issue #44783 — don't co-manage with the ASG provider in one `aws_ecs_cluster_capacity_providers`)
```hcl
resource "aws_ecs_cluster_capacity_providers" "managed_instances" {
  count              = var.enable_managed_instances ? 1 : 0
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.managed_instances[0].name]
}
```
> If `validate`/`plan` errors that the cluster's capacity providers are managed twice, gate the existing `aws_ecs_cluster_capacity_providers.this` so only one resource manages the cluster, or merge both providers into a single resource when `enable_managed_instances` is true. Decide based on the actual error.

**Step 5: Add an output**
```hcl
output "managed_instances_capacity_provider" {
  value = var.enable_managed_instances ? aws_ecs_capacity_provider.managed_instances[0].name : null
}
```

**Step 6: Verify** — `terraform validate`. Expected: valid.

**Step 7: Commit** — `feat(ecs): :sparkles: add managed instances capacity provider`

---

### Task 1.4: Support `MANAGED_INSTANCES` task defs + `privileged`/capabilities

**Files:**
- Modify: `modules/ecs/main.tf:170-203` (task definition)
- Modify: `modules/ecs/variables.tf` (extend the `tasks` container_definition type to allow `privileged` and `linuxParameters`)

**Step 1:** Ensure the `tasks` variable's `container_definition` passes through `privileged` and `linuxParameters` (the module currently `jsonencode`s `each.value.container_definition` directly at `main.tf:179-192`, so arbitrary keys already flow through — confirm the type doesn't strip them; if it's `any`, no change needed).

**Step 2:** Allow `requires_compatibilities` to be `MANAGED_INSTANCES`. The task def currently does `requires_compatibilities = [upper(var.launch_type)]` and only emits `runtime_platform` for FARGATE. Add a per-task or module-level way to set `MANAGED_INSTANCES`. Minimal approach — add an optional field:
```hcl
# variables.tf: add to each task object (or a module var)
# requires_compatibilities override, default null -> falls back to launch_type
```
In `main.tf`:
```hcl
requires_compatibilities = each.value.requires_compatibilities != null ? each.value.requires_compatibilities : [upper(var.launch_type)]
```
And emit `runtime_platform` for MANAGED_INSTANCES too (it needs `cpuArchitecture`):
```hcl
dynamic "runtime_platform" {
  for_each = contains(["FARGATE", "MANAGED_INSTANCES"], ... ) ? [1] : []
  ...
}
```

**Step 3: Verify** — `terraform validate`. Expected: valid.

**Step 4: Commit** — `feat(ecs): :sparkles: support MANAGED_INSTANCES task defs and privileged`

---

### Task 1.5: Docs + release tag

**Step 1:** Run the `tidy` skill (or `terraform fmt -recursive` + `terraform-docs`) in repo A.

**Step 2: Verify** — `git -C /Users/jkim/projects/terraform-modules diff --stat` shows only intended files; `terraform fmt -check -recursive` passes.

**Step 3: Commit + tag**
```bash
git -C /Users/jkim/projects/terraform-modules add -A
git -C /Users/jkim/projects/terraform-modules commit -m "docs: :memo: regenerate module docs"
git -C /Users/jkim/projects/terraform-modules tag 0.5.0
# push branch + tag once reviewed
```
> Per project memory: `terraform-modules` is the source of truth; this tag is what repo B will `?ref=`.

---

## Phase 2 — Webhook Lambda: routing + label uniqueness (TDD)

> All work in repo **B**, `images/webhook/`. This is the most testable phase — real TDD.

### Task 2.1: Add pytest tooling and a test file

**Files:**
- Modify: `images/webhook/environment.yml`
- Create: `images/webhook/test_lambda.py`

**Step 1:** Add to `images/webhook/environment.yml` dependencies: `pytest >=8,<9`.

**Step 2:** Create `images/webhook/test_lambda.py` with a fixture that sets all required env vars before importing `lambda` (the module instantiates `Settings()` and fetches the webhook secret at import — patch `boto3` first):
```python
import json, os, importlib
from unittest.mock import MagicMock, patch
import pytest

BASE_ENV = {
    "WEBHOOK_SECRET_SSM_PARAM": "/x/secret",
    "WEBHOOK_EVENTS": json.dumps(["workflow_job"]),
    "RUNNER_TASK_ARN": "arn:fargate-task",
    "RUNNER_TASK_NAME": "ci-runner",
    "ECS_CLUSTER": "ci-cluster",
    "ECS_SUBNET_IDS": json.dumps(["subnet-1"]),
    "ECS_SECURITY_GROUP_IDS": json.dumps(["sg-1"]),
    "LAUNCH_TYPE": "FARGATE",
    "DOCKER_RUNNER_TASK_ARN": "arn:dind-task",
    "DOCKER_RUNNER_TASK_NAME": "ci-dind",
    "MI_CAPACITY_PROVIDER": "ci-mi",
}

@pytest.fixture
def lam(monkeypatch):
    for k, v in BASE_ENV.items():
        monkeypatch.setenv(k, v)
    with patch("boto3.client") as mock_client:
        ssm = MagicMock()
        ssm.get_parameter.return_value = {"Parameter": {"Value": "secret"}}
        mock_client.return_value = ssm
        import lambda as lambda_mod  # noqa
        importlib.reload(lambda_mod)
        yield lambda_mod
```

**Step 3: Verify** — `cd images/webhook && python -m pytest -q`. Expected: 0 tests, no import/collection errors.

**Step 4: Commit** — `test(webhook): :white_check_mark: add pytest scaffold`

---

### Task 2.2: Label extraction (TDD)

**Files:** Modify `images/webhook/lambda.py`; Modify `images/webhook/test_lambda.py`

**Step 1: Failing test**
```python
def test_extract_labels_reads_workflow_job_labels(lam):
    body = {"workflow_job": {"labels": ["self-hosted", "docker"]}}
    assert lam.extract_labels(body) == {"self-hosted", "docker"}

def test_extract_labels_missing_is_empty(lam):
    assert lam.extract_labels({}) == set()
```

**Step 2: Run → FAIL** (`AttributeError: extract_labels`). Run: `python -m pytest test_lambda.py -k extract_labels -v`

**Step 3: Implement** in `lambda.py`:
```python
def extract_labels(body: Dict[str, Any]) -> Set[str]:
    return set(body.get("workflow_job", {}).get("labels", []))
```

**Step 4: Run → PASS.**

**Step 5: Commit** — `feat(lambda.py): :sparkles: extract workflow_job labels`

---

### Task 2.3: Routing decision (TDD)

**Step 1: Failing tests**
```python
def test_docker_label_routes_to_dind(lam):
    assert lam.select_target({"self-hosted", "docker"}).task_name == "ci-dind"

def test_no_docker_label_routes_to_fargate(lam):
    assert lam.select_target({"self-hosted"}).task_name == "ci-runner"
```

**Step 2: Run → FAIL.**

**Step 3: Implement.** Add a small dataclass/NamedTuple `Target(task_arn, task_name, use_mi)` and:
```python
def select_target(labels: Set[str]) -> "Target":
    if "docker" in labels:
        return Target(settings.docker_runner_task_arn, settings.docker_runner_task_name, True)
    return Target(settings.runner_task_arn, settings.runner_task_name, False)
```
Add the new fields to `Settings` (`docker_runner_task_arn`, `docker_runner_task_name`, `mi_capacity_provider`).

**Step 4: Run → PASS.**

**Step 5: Commit** — `feat(lambda.py): :sparkles: route docker-labeled jobs to DinD`

---

### Task 2.4: Build `run_task` kwargs — capacity provider, container name, unique label (TDD)

**Step 1: Failing tests**
```python
def test_dind_uses_capacity_provider_strategy(lam):
    kw = lam.build_run_task_kwargs(lam.Target("arn:dind-task", "ci-dind", True),
                                    repo_owner="o", repo_name="r")
    assert kw["capacityProviderStrategy"] == [{"capacityProvider": "ci-mi"}]
    assert "launchType" not in kw
    assert kw["overrides"]["containerOverrides"][0]["name"] == "ci-dind"

def test_fargate_uses_launch_type(lam):
    kw = lam.build_run_task_kwargs(lam.Target("arn:fargate-task", "ci-runner", False),
                                   repo_owner="o", repo_name="r")
    assert kw["launchType"] == "FARGATE"
    assert kw["overrides"]["containerOverrides"][0]["name"] == "ci-runner"

def test_unique_runner_label_env_is_set_and_distinct(lam):
    def labels(kw):
        env = kw["overrides"]["containerOverrides"][0]["environment"]
        return next(e["value"] for e in env if e["name"] == "RUNNER_LABELS")
    a = labels(lam.build_run_task_kwargs(lam.Target("a","ci-runner",False),"o","r"))
    b = labels(lam.build_run_task_kwargs(lam.Target("a","ci-runner",False),"o","r"))
    assert a != b                      # unique per call
    assert "self-hosted" in a          # base label present

def test_dind_label_includes_docker(lam):
    kw = lam.build_run_task_kwargs(lam.Target("a","ci-dind",True),"o","r")
    env = kw["overrides"]["containerOverrides"][0]["environment"]
    val = next(e["value"] for e in env if e["name"] == "RUNNER_LABELS")
    assert "docker" in val
```

**Step 2: Run → FAIL.**

**Step 3: Implement** `build_run_task_kwargs` in `lambda.py`. Generate the unique token with `uuid.uuid4().hex[:8]`. Compose `RUNNER_LABELS` = `"self-hosted"` + (`,docker` if `target.use_mi`) + `,<token>`. Set `capacityProviderStrategy`/`launchType` based on `target.use_mi`. Include the existing `GITHUB_REPO_OWNER`/`GITHUB_REPO_NAME` env entries. Network config: keep `awsvpcConfiguration` for FARGATE; for MI omit it (the capacity provider's launch template defines networking) — confirm against `run_task` behavior during the smoke test.

**Step 4: Run → PASS.**

**Step 5: Commit** — `feat(lambda.py): :sparkles: build run_task kwargs with unique labels`

---

### Task 2.5: Wire the handler to use the new functions

**Step 1: Failing test** — assert the handler path calls `ecs.run_task` with the dind kwargs when labels include `docker`:
```python
def test_handler_launches_dind(lam):
    lam.ecs.run_task = MagicMock(return_value={})
    body = {"action": "queued",
            "repository": {"owner": {"login": "o"}, "name": "r"},
            "workflow_job": {"labels": ["self-hosted", "docker"]}}
    # call the @app.post handler via app.resolve or refactor handler body into a function
    ...
    assert lam.ecs.run_task.call_args.kwargs["capacityProviderStrategy"][0]["capacityProvider"] == "ci-mi"
```

**Step 2: Run → FAIL.**

**Step 3: Implement** — refactor `handle_github_webhook` (`lambda.py:89-138`) to: parse labels via `extract_labels`, pick `select_target`, build kwargs via `build_run_task_kwargs`, call `ecs.run_task(**kwargs)`. Preserve `ping`/event-type checks and the `queued`/`completed` action handling.

**Step 4: Run → PASS.** Run the whole file: `python -m pytest -q`.

**Step 5: Commit** — `refactor(lambda.py): :recycle: route via label-based target selection`

---

## Phase 3 — DinD runner image

### Task 3.1: `setup-runner.py` — stable name + `--labels` (TDD)

**Files:** Modify `images/runner/setup-runner.py`; Create `images/runner/test_setup_runner.py`

**Step 1: Failing tests**
```python
def test_runner_name_is_stable(monkeypatch):
    # set required GITHUB_ env, import module-free helper
    ...
    s = Settings(...)
    assert s.runner_name == s.runner_name      # no fresh UUID per access

def test_config_args_include_labels(monkeypatch):
    monkeypatch.setenv("RUNNER_LABELS", "self-hosted,docker,abc123")
    args = build_config_args(token="t", url="u", name="n")
    assert "--labels" in args
    assert args[args.index("--labels") + 1] == "self-hosted,docker,abc123"
```

**Step 2: Run → FAIL.**

**Step 3: Implement**
- Make `runner_name` stable: compute the UUID once (e.g. in a `model_post_init` or a cached attribute) instead of a `@computed_field` property that re-mints on each access.
- Add `runner_labels: str = Field(default="self-hosted")` from env `RUNNER_LABELS`.
- Extract `build_config_args(...)` returning the `config.sh` arg list, appending `--labels <runner_labels>` when set. Refactor the inline `subprocess.run([... "./config.sh" ...])` (`setup-runner.py:106-119`) to use it.

**Step 4: Run → PASS.**

**Step 5: Commit** — `fix(setup-runner.py): :bug: stable name + register unique labels`

---

### Task 3.2: DinD image `FROM` the runner image

**Files:** Create `images/dind/Dockerfile`, `images/dind/entrypoint.sh`

**Step 1:** `images/dind/Dockerfile`:
```dockerfile
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER root
ENV DEBIAN_FRONTEND=noninteractive

# Docker engine (dockerd + CLI) for in-task Docker-in-Docker
RUN apt-get update && apt-get install -y --no-install-recommends \
      docker.io \
    && rm -rf /var/lib/apt/lists/*

# runneruser must reach the docker socket
RUN groupadd -f docker && usermod -aG docker runneruser

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

**Step 2:** `images/dind/entrypoint.sh` — start `dockerd`, wait for the socket, then drop to `runneruser` to run the existing setup script:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Start the Docker daemon (overlay2; privileged task provides the needed caps)
dockerd --host=unix:///var/run/docker.sock >/var/log/dockerd.log 2>&1 &

# Wait for the daemon (fail fast if it never comes up)
for i in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then break; fi
  if [ "$i" -eq 30 ]; then echo "dockerd failed to start" >&2; cat /var/log/dockerd.log >&2; exit 1; fi
  sleep 1
done

# Hand off to the runner bootstrap as the non-root user, preserving env
exec su -p runneruser -c 'source /opt/conda/etc/profile.d/conda.sh && conda activate runner && python /runner/setup-runner.py'
```
> Note: this entrypoint runs as root so `dockerd` can start; `su` drops the runner agent to `runneruser` (which is in the `docker` group). Confirm the runner image's `setup-runner.py` path (`/runner/setup-runner.py`) and conda env name (`runner`) match `images/runner/Dockerfile`.

**Step 3: Verify (local build smoke).** Requires the runner image built locally; for a standalone check, temporarily build with a stub base:
```bash
docker build --build-arg BASE_IMAGE=ubuntu:22.04 -t dind-smoke images/dind   # expect failure only at conda/runner paths, not Docker syntax
```
Primary verification is the end-to-end deploy in Phase 5. At minimum, `hadolint images/dind/Dockerfile` (if available) and `bash -n images/dind/entrypoint.sh` (syntax check) must pass.

**Step 4: Commit** — `feat(dind): :sparkles: docker-in-docker runner image`

---

## Phase 4 — Wire it into the root module

> Repo **B**, root `main.tf` / `variables.tf`. The Fargate path must remain unchanged.

### Task 4.1: Bump module refs to `0.5.0`

**Files:** Modify `main.tf` (the `vpc`/`runner`/`ecs`/`webhook` `source` refs currently `?ref=0.4.1`).

**Step 1:** Bump the `ecs`, `runner`, and (new) `docker` consumer refs to `?ref=0.5.0`. Leave others as-is unless they changed.

**Step 2: Verify** — `cd deployment && terraform init -upgrade && terraform validate`. Expected: valid (module downloads at 0.5.0).
> Requires the 0.5.0 tag pushed in Task 1.5.

**Step 3: Commit** — `chore(main.tf): :arrow_up: bump terraform-modules to 0.5.0`

---

### Task 4.2: Build the DinD image module

**Files:** Modify `main.tf`, `variables.tf`

**Step 1:** Add a variable `dind_image_tag` (mirror `runner_image_tag`) to `variables.tf`.

**Step 2:** Add to `main.tf`:
```hcl
module "dind" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/docker?ref=0.5.0"

  image_name    = "${var.name}-dind"
  image_tag     = var.dind_image_tag
  build_context = "${path.module}/images/dind"
  platform      = "linux/${var.architecture}"
  build_args    = { BASE_IMAGE = "${module.runner.ecr_repo.repository_url}@${module.runner.image.sha256_digest}" }

  depends_on = [module.runner]
}
```

**Step 3: Verify** — `terraform validate`. Expected: valid.

**Step 4: Commit** — `feat(main.tf): :sparkles: build DinD runner image`

---

### Task 4.3: Add the DinD task + enable Managed Instances on the `ecs` module

**Files:** Modify `main.tf`

**Step 1:** Enable MI on the `ecs` module call:
```hcl
  enable_managed_instances        = true
  managed_instances_allow_privileged = true
  # managed_instances_instance_requirements = { ... }  # optional attribute-based selection
```

**Step 2:** Add a second entry to the `ecs` module's `tasks` map for the DinD runner — same shape as the existing runner task (`main.tf:42-102`) but:
- `name`/`image` from `module.dind`
- add `privileged = true` to the container definition
- add `linuxParameters = { capabilities = { add = ["SYS_ADMIN", "NET_ADMIN"] } }`
- set `requires_compatibilities = ["MANAGED_INSTANCES"]` (per Task 1.4's mechanism)
- keep the same SSM/ECR IAM blocks (the DinD runner still self-registers via the GitHub App)

**Step 3: Verify** — `terraform validate`. Expected: valid.

**Step 4: Commit** — `feat(main.tf): :sparkles: add privileged DinD task on managed instances`

---

### Task 4.4: Wire Lambda env vars

**Files:** Modify `main.tf:129-138` (the `lambda` module `environment_variables`)

**Step 1:** Add:
```hcl
    DOCKER_RUNNER_TASK_ARN  = module.ecs.task_definitions[module.dind.image_name].arn
    DOCKER_RUNNER_TASK_NAME = module.dind.image_name
    MI_CAPACITY_PROVIDER    = module.ecs.managed_instances_capacity_provider
```

**Step 2:** Ensure the Lambda's `ecs:RunTask` IAM (in `modules/lambda/main.tf:25-34`) covers the new DinD task definition ARN — `var.ecs_task_definition_arns` already passes `[for task in module.ecs.task_definitions : task.arn]` (`main.tf:121`), which now includes the DinD task. Confirm. Also confirm `iam:PassRole` covers the DinD task role (it iterates `module.ecs.task_roles`).

**Step 3: Verify** — `terraform validate` then `cd deployment && terraform plan`. Expected: a clean plan adding the MI capacity provider, infra role, DinD ECR repo/image, DinD task def, and Lambda env-var updates; **no changes to the existing Fargate runner task**.

**Step 4: Commit** — `feat(main.tf): :sparkles: pass DinD + MI config to webhook lambda`

---

### Task 4.5: Regenerate docs

**Step 1:** Run the `tidy` skill in repo B (terraform fmt + terraform-docs updates `README.md`).

**Step 2: Verify** — `terraform fmt -check -recursive` passes; `README.md` lists the new `dind_image_tag` input.

**Step 3: Commit** — `docs(README.md): :memo: document DinD inputs`

---

## Phase 5 — Deploy + end-to-end verification

> REQUIRED SKILL when verifying behavior: superpowers:verification-before-completion (evidence before claims).

### Task 5.1: Apply

**Step 1:** `cd deployment && terraform apply`. Watch for MI capacity-provider creation and DinD image push.
**Step 2: Verify** — apply succeeds; in the ECS console the cluster shows the MI capacity provider; no running instances (scale-to-zero) when idle.

### Task 5.2: DinD smoke test

**Step 1:** In a target repo, add a workflow:
```yaml
on: workflow_dispatch
jobs:
  build:
    runs-on: [self-hosted, docker]
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t smoke-test .
```
**Step 2:** Trigger it. 
**Step 3: Verify (evidence):**
- ECS provisions an MI instance and runs the DinD task (capture task ARN + `RUNNING`).
- The job's `docker build` step succeeds in the Actions logs.
- After completion the task stops and the instance drains → cluster returns to **zero** instances.

### Task 5.3: Label-uniqueness regression check

**Step 1:** Trigger **3+ concurrent** jobs across the Fargate and DinD label sets.
**Step 2: Verify (evidence):** every queued job is picked up (none stuck "queued" with idle runners online). Confirm in GitHub's runner list that each ephemeral runner carries a distinct `RUNNER_LABELS` token. This is the fix for community #120813.

### Task 5.4: Finish the branch

Use superpowers:finishing-a-development-branch to open PRs for both repos (A first — B depends on the 0.5.0 tag).

---

## Open items to resolve during execution (from design)
- **Task 1.3** confirms the exact MI privileged-capability opt-in argument name — do not skip the schema dump.
- Architecture is **arm64** to match the existing runner (`linux-arm64`, `aarch64`); MI instance requirements must select arm64 instance types. If you switch to x86_64, update both runner and DinD image arch + the runner download in `images/runner/Dockerfile`.
- Confirm whether MI `run_task` needs `networkConfiguration` omitted (capacity-provider launch template owns networking) — settle empirically in Task 5.2.
