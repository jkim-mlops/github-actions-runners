import json
import hashlib
import hmac
from typing import Any, Dict, List, Set
import boto3
from aws_lambda_powertools.event_handler import (
    APIGatewayRestResolver,
    Response,
    content_types,
)
from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools.logging import Logger
from pydantic import Field
from pydantic_settings import BaseSettings


# Pydantic settings for environment variables
class Settings(BaseSettings):
    webhook_secret_ssm_param: str = Field(default=...)
    webhook_events: str = Field(default=...)
    runner_task_arn: str = Field(default=...)
    runner_task_name: str = Field(default=...)
    ecs_cluster: str = Field(default=...)
    ecs_subnet_ids: str = Field(default=...)
    ecs_security_group_ids: str = Field(default=...)
    launch_type: str = Field(default=...)

    @property
    def events(self) -> Set[str]:
        return set(json.loads(self.webhook_events))

    @property
    def subnet_ids(self) -> List[str]:
        return json.loads(self.ecs_subnet_ids)

    @property
    def security_group_ids(self) -> List[str]:
        return json.loads(self.ecs_security_group_ids)


settings = Settings()
logger = Logger()
app = APIGatewayRestResolver()
ecs = boto3.client("ecs")


def get_webhook_secret():
    ssm = boto3.client("ssm")
    response = ssm.get_parameter(
        Name=settings.webhook_secret_ssm_param, WithDecryption=True
    )
    return response["Parameter"]["Value"]


WEBHOOK_SECRET = get_webhook_secret()


@app.exception_handler(ValueError)
def handle_unauthorized(ex: ValueError) -> Response:  # receives exception raised
    metadata = {
        "path": app.current_event.path,
        "query_strings": app.current_event.query_string_parameters,
    }
    logger.error(f"Unauthorized request: {ex}", extra=metadata)

    return Response(
        status_code=403,
        content_type=content_types.APPLICATION_JSON,
        body={"error": "Unauthorized", "message": str(ex)},
    )


def verify_signature(
    payload_body: bytes, secret_token: str, signature_header: str
) -> None:
    """Verify that the payload was sent from GitHub by validating SHA256.

    Raise and return 403 if not authorized.

    Args:
        payload_body: original request body to verify (request.body())
        secret_token: GitHub app webhook token (WEBHOOK_SECRET)
        signature_header: header received from GitHub (x-hub-signature-256)
    """
    if not signature_header:
        raise ValueError("x-hub-signature-256 header is missing!")
    hash_object = hmac.new(
        secret_token.encode("utf-8"), msg=payload_body, digestmod=hashlib.sha256
    )
    expected_signature = "sha256=" + hash_object.hexdigest()
    if not hmac.compare_digest(expected_signature, signature_header):
        raise ValueError("Request signatures didn't match!")


@app.post("/webhook")
def handle_github_webhook():
    # Only accept workflow_job events
    event_type = app.current_event.headers.get(
        "X-GitHub-Event"
    ) or app.current_event.headers.get("x-github-event")
    if event_type == "ping":
        return {"status": "ping accepted"}
    elif event_type not in settings.events:
        raise ValueError(f"Unsupported event type: {event_type}")

    # Parse repo_owner and repo_name from event body (assume JSON payload)
    body = app.current_event.json_body
    repo_owner = body.get("repository", {}).get("owner", {}).get("login")
    repo_name = body.get("repository", {}).get("name")

    response = ecs.run_task(
        cluster=settings.ecs_cluster,
        launchType="FARGATE",
        taskDefinition=settings.runner_task_arn,
        count=1,
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": settings.subnet_ids,
                "securityGroups": settings.security_group_ids,
                "assignPublicIp": "ENABLED",
            }
        },
        overrides={
            "containerOverrides": [
                {
                    "name": settings.runner_task_name,  # must match container name in task def
                    "environment": [
                        {"name": "GITHUB_REPO_OWNER", "value": repo_owner},
                        {"name": "GITHUB_REPO_NAME", "value": repo_name},
                    ],
                }
            ]
        },
        # capacityProviderStrategy=[{"capacityProvider": "FARGATE", "weight": 1}],
    )
    logger.debug(response)

    return {"message": "ECS task launched"}


@logger.inject_lambda_context(log_event=True)
def handler(event: Dict[str, Any], context: LambdaContext) -> Dict[str, Any]:
    # Extract signature from headers
    headers: Dict[str, str] = event.get("headers", {})
    signature_header = headers.get("x-hub-signature-256", "") or headers.get(
        "X-Hub-Signature-256", ""
    )

    # Get raw request body
    raw_body = event.get("body", "")
    payload_body = raw_body.encode("utf-8") if isinstance(raw_body, str) else raw_body

    # Verify the signature
    verify_signature(payload_body, WEBHOOK_SECRET, signature_header)

    return app.resolve(event, context)
