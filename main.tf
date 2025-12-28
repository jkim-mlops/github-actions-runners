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
  image_tag     = "0.1.0"
  build_context = "${path.module}/images/runner"
  platform      = "linux/arm64"
}

module "ecs" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/ecs?ref=0.1.1"

  name            = var.name
  cidr_blocks     = [module.vpc.vpc_cidr_block]
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  architecture    = var.architecture
  instance_type   = var.instance_type
  logging_enabled = true
  aws_region      = var.region
  tasks = {
    "${module.runner.image_name}" = {
      container_definition = {
        name      = module.runner.image_name
        image     = "${module.runner.ecr_repo.repository_url}:${module.runner.image_tag}"
        cpu       = var.cpu
        memory    = var.memory
        essential = true
        environment = [
          {
            name  = "AWS_SDK_LOAD_CONFIG"
            value = true
          },
          {
            name  = "GITHUB_APP_CLIENT_ID_PARAM_NAME"
            value = var.github_app_client_id_param_name
          },
          {
            name  = "GITHUB_APP_PRIVATE_KEY_PARAM_NAME"
            value = var.github_app_private_key_param_name
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
  image_tag     = "0.2.0"
  build_context = "${path.module}/images/webhook"
  platform      = "linux/arm64"
}

module "lambda" {
  for_each = toset(var.repository_names)
  source   = "./modules/lambda"

  name                        = "${var.name}-webhook-${each.value}"
  image_uri                   = "${module.webhook.ecr_repo.repository_url}@${module.webhook.image.sha256_digest}"
  ecs_task_definition_arns    = [for task in module.ecs.task_definitions : task.arn]
  ecs_task_execution_role_arn = module.ecs.task_execution_role.arn
  ecs_task_role_arns          = [for role in module.ecs.task_roles : role.arn]

  depends_on = [ module.webhook ]
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
