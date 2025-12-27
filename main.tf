/**
* # deployment
*
* End-to-end deployment of Github Actions runners.
*
* ## Features
* * Support for secure, cost-efficient container builds with **kaniko**.
*/

module "vpc" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/vpc?ref=0.1.0"

  name       = var.name
  region     = data.aws_region.this.id
  cidr_block = var.cidr_block
  subnets    = var.subnets
}



module "runner" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/docker?ref=0.1.0"

  image_name    = "${var.name}-runner"
  image_tag     = "0.1.0"
  build_context = "./images/runner"
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
  aws_region      = data.aws_region.this.id
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
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/docker?ref=0.1.0"

  image_name    = "${var.name}-webhook"
  image_tag     = "0.1.0"
  build_context = "./images/webhook"
}

module "lambda" {
  source = "./modules/lambda"

  name = "${var.name}-webhook"
  image_uri = "${module.webhook.ecr_repo.repository_url}:${module.webhook.image_tag}"
  ecs_task_definition_arns = module.ecs.ecs_task_definition_arns
  ecs_task_execution_role_arn = module.ecs.ecs_task_execution_role_arn
  ecs_task_role_arns = module.ecs.ecs_task_role_arns
}