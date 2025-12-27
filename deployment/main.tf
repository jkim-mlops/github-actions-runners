data "aws_region" "this" {}

locals {
  github_app_name = "gh-actions-jkim-mlops"
  github_owner    = "jkim-mlops"
}

# You should have a scoped token for creating webhooks already created in ssm.

data "aws_ssm_parameter" "github_token" {
    name = "/github/deployments/webhook/token"
}

# The GitHub provider doesn't support creating apps.
# You are expected to have created the app and store the parameters beforehand.

data "aws_ssm_parameter" "github_app_client_id" {
  name            = "/github/apps/${local.github_app_name}/client-id"
}

data "aws_ssm_parameter" "github_app_private_key" {
  name            = "/github/apps/${local.github_app_name}/private-key"
}

module "main" {
  source = ".."

  architecture                      = "arm64"
  cidr_block                        = "10.0.0.0/16"
  cpu                               = 1024 * 2
  github_app_client_id_param_name   = data.aws_ssm_parameter.github_app_client_id.name
  github_app_private_key_param_name = data.aws_ssm_parameter.github_app_private_key.name
  github_app_ssm_param_arns = [
    data.aws_ssm_parameter.github_app_client_id.arn,
    data.aws_ssm_parameter.github_app_private_key.arn
  ]
  instance_type                     = "m6g.large"
  memory                            = 1048 * 4
  name                              = "gh-actions-${terraform.workspace}"
  repository_name                   = "github-actions-runners"
  webhook_events                    = ["workflow_job"]
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
}