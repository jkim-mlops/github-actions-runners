FROM public.ecr.aws/lambda/python:3.13-arm64

# Install Python dependencies
RUN pip install --no-cache-dir \
    "awslambdaric>=3.1,<4" \
    "aws-lambda-powertools>=3.23,<4" \
    "boto3>=1.40,<2" \
    "pydantic>=2,<3" \
    "pydantic-settings>=2,<3"

# Copy function code
COPY webhook.py ${LAMBDA_TASK_ROOT}/

# Set the CMD to your handler
CMD ["webhook.handler"]
