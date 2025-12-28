FROM public.ecr.aws/lambda/python:3.13-arm64

# Install Python dependencies
RUN pip install --no-cache-dir \
    "awslambdaric>=3.1,<4" \
    "aws-lambda-powertools>=3.23,<4"

# Copy function code
COPY lambda.py ${LAMBDA_TASK_ROOT}/

# Set the CMD to your handler
CMD ["lambda.handler"]
