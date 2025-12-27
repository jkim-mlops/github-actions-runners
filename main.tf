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

module "docker" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/docker?ref=0.1.0"

  image_name    = var.name
  image_tag     = "0.1.0"
  build_context = "./docker"
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
    "${module.docker.image_name}" = {
      container_definition = {
        name      = module.docker.image_name
        image     = "${module.docker.ecr_repo.repository_url}:${module.docker.image_tag}"
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
