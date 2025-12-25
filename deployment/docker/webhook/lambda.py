import hashlib
import hmac
import os
from typing import Any, Dict
from aws_lambda_powertools.event_handler import (
    APIGatewayRestResolver,
    Response,
    content_types,
)
from aws_lambda_powertools.utilities.typing import LambdaContext
from aws_lambda_powertools.logging import Logger

logger = Logger()
app = APIGatewayRestResolver()

WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")


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


@app.get("/webhook")
def handle_github_webhook():
    payload = app.current_event.json_body
    return {
        "message": "hello world"
    }  # Powertools automatically handles the response format


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
