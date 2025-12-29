/**
* # github-actions-runners
*
* End-to-end deployment of self-hosted GitHub Actions runners.
*
* ## Features
* * Support for secure, cost-efficient container builds with **kaniko**.
*/

module "vpc" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/vpc?ref=0.1.0"

  name       = var.name
  region     = var.region
  cidr_block = var.cidr_block
  subnets    = var.subnets
}

module "runner" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/docker?ref=0.1.2"

  image_name    = "${var.name}-runner"
  image_tag     = var.runner_image_tag
  build_context = "${path.module}/images/runner"
  platform      = "linux/${var.architecture}"
}

module "ecs" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/ecs?ref=feat/fargate-cp"

  name               = var.name
  cidr_blocks        = [module.vpc.vpc_cidr_block]
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  architecture       = var.architecture
  instance_type      = var.instance_type
  launch_type        = "FARGATE"
  logging_enabled    = true
  log_retention_days = 1
  aws_region         = var.region
  tasks = {
    "${module.runner.image_name}" = {
      container_definition = {
        name      = module.runner.image_name
        image     = "${module.runner.ecr_repo.repository_url}@${module.runner.image.sha256_digest}"
        cpu       = var.cpu
        memory    = var.memory
        essential = true
        environment = [
          {
            name  = "AWS_SDK_LOAD_CONFIG"
            value = true
          },
          {
            name  = "GITHUB_APP_CLIENT_ID_PARAM"
            value = var.github_app_client_id_param
          },
          {
            name  = "GITHUB_APP_PRIVATE_KEY_PARAM"
            value = var.github_app_private_key_param
          },
          {
            name  = "GITHUB_APP_INSTALLATION_ID"
            value = var.github_app_installation_id
          }
        ]
      }
      iam = {
        ecrPermissions = {
          actions = [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:PutImage",
            "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:CompleteLayerUpload",
            "ecr:CreateRepository",
            "ecr:DescribeRepositories"
          ]
          resources = ["*"]
        }
        ssmPermissions = {
          actions = [
            "ssm:GetParameter",
            "ssm:GetParameters",
            "ssm:GetParametersByPath"
          ]
          resources = var.github_app_ssm_param_arns
        }
        kmsPermissions = {
          actions = [
            "kms:Decrypt"
          ]
          resources = var.github_app_ssm_param_arns
        }
      }
    }
  }
}

module "webhook" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/docker?ref=0.1.2"

  image_name    = "${var.name}-webhook"
  image_tag     = var.webhook_image_tag
  build_context = "${path.module}/images/webhook"
  platform      = "linux/${var.architecture}"
}

module "lambda" {
  for_each = toset(var.repository_names)
  source   = "./modules/lambda"

  name                        = "${var.name}-webhook-${each.value}"
  image_uri                   = "${module.webhook.ecr_repo.repository_url}@${module.webhook.image.sha256_digest}"
  ecs_task_definition_arns    = [for task in module.ecs.task_definitions : task.arn]
  ecs_task_execution_role_arn = module.ecs.task_execution_role.arn
  ecs_task_role_arns          = [for role in module.ecs.task_roles : role.arn]

  vpc_subnet_ids = module.vpc.private_subnet_ids
  vpc_id         = module.vpc.vpc_id
  architectures  = [var.architecture]

  environment_variables = {
    WEBHOOK_EVENTS         = jsonencode(var.webhook_events)
    RUNNER_TASK_ARN        = module.ecs.task_definitions[module.runner.image_name].arn
    RUNNER_TASK_NAME       = module.runner.image_name
    ECS_CLUSTER            = module.ecs.cluster.id
    ECS_SUBNET_IDS         = jsonencode(module.vpc.private_subnet_ids)
    ECS_SECURITY_GROUP_IDS = jsonencode([module.ecs.security_group.id])
    LAUNCH_TYPE            = "FARGATE"
  }
  depends_on = [module.webhook]
}

module "api_gateway" {
  for_each = toset(var.repository_names)
  source   = "./modules/api_gateway"

  name       = "${var.name}-webhook-${each.value}"
  stage_name = var.stage_name
  lambda     = module.lambda[each.key].lambda
}

# Create webhook for each repository
resource "github_repository_webhook" "this" {
  for_each   = toset(var.repository_names)
  repository = each.value
  active     = true

  configuration {
    url          = module.api_gateway[each.key].webhook_url
    content_type = "json"
    secret       = module.lambda[each.key].webhook_secret
    insecure_ssl = false
  }

  events = var.webhook_events
}
