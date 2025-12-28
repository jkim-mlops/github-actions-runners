data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
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

  statement {
    effect = "Allow"
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
}

# Generate a random alphanumeric secret for webhook
resource "random_string" "webhook_secret" {
  length  = var.webhook_secret_length
  special = false
  upper   = true
  lower   = true
  numeric = true
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

resource "aws_lambda_function" "this" {
  function_name = var.name
  role          = aws_iam_role.this.arn
  package_type  = "Image"
  image_uri     = var.image_uri 

  image_config {
    command     = ["lambda.handler"]
  }

  environment {
    variables = var.environment_variables
  }

  memory_size = 512
  timeout     = 30

  architectures = ["arm64"] # Graviton support for better price/performance
}

