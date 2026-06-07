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
