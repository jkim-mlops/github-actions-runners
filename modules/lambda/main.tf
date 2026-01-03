/**
* # Lambda Webhook Handler Module
*
* Creates a Lambda function to handle GitHub webhook events and trigger ECS tasks for self-hosted runners.
*
* ## Features
* * Generates secure webhook secret
* * IAM roles with ECS task execution permissions
* * Container-based Lambda function
* * Environment variable configuration support
*/

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_run_task" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "ecs:DescribeTasks",
      "ecs:StopTask"
    ]
    resources = var.ecs_task_definition_arns
  }

  # Allow Lambda to manage network interfaces for VPC access
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface"
    ]
    resources = ["*"]
  }

  statement {
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = concat(
      [var.ecs_task_execution_role_arn],
      var.ecs_task_role_arns
    )

    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # Allow Lambda to get the webhook secret from SSM Parameter Store
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters"
    ]
    resources = [aws_ssm_parameter.webhook_secret.arn]
  }
}

# Generate a random alphanumeric secret for webhook
resource "random_string" "webhook_secret" {
  length  = var.webhook_secret_length
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# Store the webhook secret in SSM Parameter Store
resource "aws_ssm_parameter" "webhook_secret" {
  name        = "/github-actions-runners/${var.name}/webhook_secret"
  description = "GitHub Actions Runner Webhook Secret for ${var.name}"
  type        = "SecureString"
  value       = random_string.webhook_secret.result
  overwrite   = true
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "ecs_run_task" {
  name   = "${var.name}-ecs-run-task"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.ecs_run_task.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_security_group" "lambda" {
  name        = "${var.name}-lambda-sg"
  description = "Security group for Lambda function ${var.name}"
  vpc_id      = var.vpc_id

  # Egress rule: allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lambda_function" "this" {
  function_name = var.name
  role          = aws_iam_role.this.arn
  package_type  = "Image"
  image_uri     = var.image_uri

  image_config {
    command = ["lambda.handler"]
  }

  environment {
    variables = merge(
      var.environment_variables,
      {
        WEBHOOK_SECRET_SSM_PARAM = aws_ssm_parameter.webhook_secret.name,
      }
    )
  }

  memory_size = 256
  timeout     = 15

  architectures = var.architectures

  vpc_config {
    subnet_ids         = var.vpc_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }
}

