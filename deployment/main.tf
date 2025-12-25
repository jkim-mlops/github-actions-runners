/**
* # deployment
*
* End-to-end deployment of Github Actions runners.
*
* ## Features
* * Support for secure, cost-efficient container builds with **kaniko**.
*/
locals {
  name = "gh-actions-runners-${terraform.workspace}"
  github_app_client_id_param_name = "/github/apps/${var.github_app_name}/client-id"
  github_app_private_key_param_name = "/github/apps/${var.github_app_name}/private-key"
}

data "aws_region" "this" {}

data "aws_ssm_parameter" "github_app_client_id" {
  name = local.github_app_client_id_param_name 
  with_decryption = true
}

data "aws_ssm_parameter" "github_app_private_key" {
  name            = local.github_app_private_key_param_name
  with_decryption = true
}

module "vpc" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/vpc?ref=0.1.0"

  name       = local.name
  region     = data.aws_region.this.id
  cidr_block = var.cidr_block
  subnets    = var.subnets
}

module "docker" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/docker?ref=0.1.0"

  image_name    = local.name
  image_tag     = "0.1.0"
  build_context = "./docker"
}

module "ecs" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/ecs?ref=0.1.1"

  name            = local.name
  cidr_blocks     = [module.vpc.vpc_cidr_block]
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  architecture    = "arm64"
  instance_type   = "m6g.large"
  logging_enabled = true
  aws_region      = data.aws_region.this.id
  tasks = {
    "${module.docker.image_name}" = {
      container_definition = {
        name      = module.docker.image_name
        image     = "${module.docker.ecr_repo.repository_url}:${module.docker.image_tag}"
        cpu       = 1024 * 2
        memory    = 1048 * 4
        essential = true
        environment = [
          {
            name  = "AWS_SDK_LOAD_CONFIG"
            value = true
          },
          {
            name  = "GITHUB_APP_CLIENT_ID_PARAM_NAME"
            value = local.github_app_client_id_param_name
          },
          {
            name  = "GITHUB_APP_PRIVATE_KEY_PARAM_NAME"
            value = local.github_app_private_key_param_name
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
          resources = [
            data.aws_ssm_parameter.github_app_client_id.arn,
            data.aws_ssm_parameter.github_app_private_key.arn
          ]
        }
        kmsPermissions = {
          actions = [
            "kms:Decrypt"
          ]
          resources = [
            data.aws_ssm_parameter.github_app_client_id.arn,
            data.aws_ssm_parameter.github_app_private_key.arn
          ]
        }
      }
    }
  }
}
