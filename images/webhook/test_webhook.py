import importlib
import json

import boto3
import pytest
from moto import mock_aws

WEBHOOK_SECRET_PARAM = "/github-actions-runners/ci/webhook_secret"
WEBHOOK_SECRET_VALUE = "supersecret"

# Minimal environment so `Settings()` validates when the module is imported.
BASE_ENV = {
    "WEBHOOK_SECRET_SSM_PARAM": WEBHOOK_SECRET_PARAM,
    "WEBHOOK_EVENTS": json.dumps(["workflow_job"]),
    "FARGATE_RUNNER_TASK_ARN": "arn:aws:ecs:us-east-1:123456789012:task-definition/ci-runner:1",
    "FARGATE_RUNNER_TASK_NAME": "ci-runner",
    "ECS_CLUSTER": "ci-cluster",
    "ECS_SUBNET_IDS": json.dumps(["subnet-1"]),
    "ECS_SECURITY_GROUP_IDS": json.dumps(["sg-1"]),
    "LAUNCH_TYPE": "FARGATE",
    "DIND_RUNNER_TASK_ARN": "arn:aws:ecs:us-east-1:123456789012:task-definition/ci-dind:1",
    "DIND_RUNNER_TASK_NAME": "ci-dind",
    "MI_CAPACITY_PROVIDER": "ci-mi",
    # Region + dummy creds so boto3 builds clients (moto intercepts the calls).
    "AWS_DEFAULT_REGION": "us-east-1",
    "AWS_ACCESS_KEY_ID": "testing",
    "AWS_SECRET_ACCESS_KEY": "testing",
    "AWS_SESSION_TOKEN": "testing",
}


@pytest.fixture
def webhook_mod(monkeypatch):
    """Import webhook.py under a moto-mocked AWS with the secret pre-created.

    The module reads SSM and builds an ECS client at import time, so env +
    moto must be active first. We reload inside the mock so module-level state
    binds to this test's mocked AWS.
    """
    for key, value in BASE_ENV.items():
        monkeypatch.setenv(key, value)
    with mock_aws():
        boto3.client("ssm").put_parameter(
            Name=WEBHOOK_SECRET_PARAM,
            Value=WEBHOOK_SECRET_VALUE,
            Type="SecureString",
        )
        import webhook

        importlib.reload(webhook)
        yield webhook


def test_fixture_loads_module(webhook_mod):
    # Proves the import + moto-backed SSM read works end to end.
    assert webhook_mod.WEBHOOK_SECRET == WEBHOOK_SECRET_VALUE


def test_extract_labels_reads_workflow_job_labels(webhook_mod):
    body = {"workflow_job": {"labels": ["self-hosted", "docker"]}}
    assert webhook_mod.extract_labels(body) == ["self-hosted", "docker"]


def test_extract_labels_missing_is_empty(webhook_mod):
    assert webhook_mod.extract_labels({}) == []


def test_docker_label_routes_to_dind(webhook_mod):
    target = webhook_mod.select_target(["self-hosted", "docker"])
    assert target.task_name == "ci-dind"
    assert target.task_arn == BASE_ENV["DIND_RUNNER_TASK_ARN"]
    assert target.use_mi is True


def test_no_docker_label_routes_to_fargate(webhook_mod):
    target = webhook_mod.select_target(["self-hosted"])
    assert target.task_name == "ci-runner"
    assert target.task_arn == BASE_ENV["FARGATE_RUNNER_TASK_ARN"]
    assert target.use_mi is False


def _runner_labels(kwargs):
    env = kwargs["overrides"]["containerOverrides"][0]["environment"]
    return next(e["value"] for e in env if e["name"] == "RUNNER_LABELS")


def test_dind_uses_capacity_provider_strategy(webhook_mod):
    kw = webhook_mod.build_run_task_kwargs(
        webhook_mod.Target("arn:dind", "ci-dind", True), repo_owner="o", repo_name="r"
    )
    assert kw["capacityProviderStrategy"] == [{"capacityProvider": "ci-mi"}]
    assert "launchType" not in kw
    assert kw["taskDefinition"] == "arn:dind"
    assert kw["overrides"]["containerOverrides"][0]["name"] == "ci-dind"


def test_fargate_uses_launch_type(webhook_mod):
    kw = webhook_mod.build_run_task_kwargs(
        webhook_mod.Target("arn:fargate", "ci-runner", False), repo_owner="o", repo_name="r"
    )
    assert kw["launchType"] == "FARGATE"
    assert "capacityProviderStrategy" not in kw
    assert kw["overrides"]["containerOverrides"][0]["name"] == "ci-runner"
    assert "awsvpcConfiguration" in kw["networkConfiguration"]


def test_unique_runner_label_is_set_and_distinct(webhook_mod):
    a = _runner_labels(webhook_mod.build_run_task_kwargs(webhook_mod.Target("a", "ci-runner", False), "o", "r"))
    b = _runner_labels(webhook_mod.build_run_task_kwargs(webhook_mod.Target("a", "ci-runner", False), "o", "r"))
    assert a != b  # unique per launch
    assert "self-hosted" in a


def test_dind_labels_include_docker(webhook_mod):
    val = _runner_labels(webhook_mod.build_run_task_kwargs(webhook_mod.Target("a", "ci-dind", True), "o", "r"))
    assert "docker" in val


def test_repo_env_overrides_present(webhook_mod):
    env = webhook_mod.build_run_task_kwargs(
        webhook_mod.Target("a", "ci-runner", False), "owner1", "repo1"
    )["overrides"]["containerOverrides"][0]["environment"]
    by_name = {e["name"]: e["value"] for e in env}
    assert by_name["GITHUB_REPO_OWNER"] == "owner1"
    assert by_name["GITHUB_REPO_NAME"] == "repo1"


@pytest.fixture
def ecs_client(webhook_mod):
    """A moto-backed ECS client with the cluster and both task defs registered."""
    client = boto3.client("ecs")
    client.create_cluster(clusterName="ci-cluster")
    for family in ("ci-runner", "ci-dind"):
        client.register_task_definition(
            family=family,
            containerDefinitions=[{"name": family, "image": "x:latest", "memory": 512}],
        )
    return client


@pytest.fixture
def job_body():
    """Factory for a workflow_job webhook body with the given labels."""

    def _make(labels):
        return {
            "action": "queued",
            "repository": {"owner": {"login": "o"}, "name": "r"},
            "workflow_job": {"labels": labels},
        }

    return _make


def test_launch_runner_fargate_starts_task(webhook_mod, ecs_client, job_body):
    webhook_mod.launch_runner(job_body(["self-hosted"]))
    task_arns = ecs_client.list_tasks(cluster="ci-cluster")["taskArns"]
    assert len(task_arns) == 1
    desc = ecs_client.describe_tasks(cluster="ci-cluster", tasks=task_arns)["tasks"][0]
    assert "ci-runner" in desc["taskDefinitionArn"]


def test_launch_runner_dind_targets_mi(webhook_mod, job_body, monkeypatch):
    # moto's run_task doesn't model MI capacity providers, so capture the call
    # and assert the DinD path targets the MI capacity provider.
    captured = {}

    def fake_run_task(**kwargs):
        captured.update(kwargs)
        return {}

    monkeypatch.setattr(webhook_mod.ecs, "run_task", fake_run_task)
    webhook_mod.launch_runner(job_body(["self-hosted", "docker"]))

    assert captured["taskDefinition"] == BASE_ENV["DIND_RUNNER_TASK_ARN"]
    assert captured["capacityProviderStrategy"] == [{"capacityProvider": "ci-mi"}]
    assert "launchType" not in captured
