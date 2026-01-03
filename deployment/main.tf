/**
* # Deployment Configuration
*
* Environment-specific deployment configuration for GitHub Actions runners.
* Orchestrates the main module with GitHub App credentials and repository webhooks.
*
* ## Features
* * Workspace-based environment management
* * GitHub App authentication via SSM parameters
* * Repository webhook configuration
*/

data "aws_region" "this" {}

locals {
  github_app_name            = "gh-actions-jkim-mlops"
  github_app_installation_id = "101115683"
  github_owner               = "jkim-mlops"
}

# You should have a scoped token for creating webhooks already created in ssm.

data "aws_ssm_parameter" "github_token" {
  name = "/github/deployments/webhook/token"
}

# The GitHub provider doesn't support creating apps.
# You are expected to have created the app and store the parameters beforehand.

data "aws_ssm_parameter" "github_app_client_id" {
  name = "/github/apps/${local.github_app_name}/client-id"
}

data "aws_ssm_parameter" "github_app_private_key" {
  name = "/github/apps/${local.github_app_name}/private-key"
}

module "main" {
  github_app_installation_id = local.github_app_installation_id
  source                     = "./.."

  providers = {
    github = github
  }

  # General
  name   = "gh-actions-${terraform.workspace}"
  region = data.aws_region.this.id

  # Image tags
  runner_image_tag  = "0.1.0"
  webhook_image_tag = "0.2.0"

  # Compute/Platform
  architecture  = "arm64"
  instance_type = "m6g.large"
  cpu           = 1024 * 2
  memory        = 1024 * 4

  # Networking
  cidr_block = "10.0.0.0/16"
  subnets = {
    a-public = {
      availability_zone = "${data.aws_region.this.id}a"
      cidr_block        = "10.0.1.0/24"
      public            = true
    }
    b-public = {
      availability_zone = "${data.aws_region.this.id}b"
      cidr_block        = "10.0.2.0/24"
      public            = true
    }
    a-private = {
      availability_zone = "${data.aws_region.this.id}a"
      cidr_block        = "10.0.3.0/24"
      public            = false
    }
    b-private = {
      availability_zone = "${data.aws_region.this.id}b"
      cidr_block        = "10.0.4.0/24"
      public            = false
    }
  }

  # GitHub App
  github_app_client_id_param   = data.aws_ssm_parameter.github_app_client_id.name
  github_app_private_key_param = data.aws_ssm_parameter.github_app_private_key.name
  github_app_ssm_param_arns = [
    data.aws_ssm_parameter.github_app_client_id.arn,
    data.aws_ssm_parameter.github_app_private_key.arn
  ]

  # Webhook/Repos
  repository_names = ["tradestation-python-ci"]
  webhook_events   = ["workflow_job"]
  stage_name       = terraform.workspace
}