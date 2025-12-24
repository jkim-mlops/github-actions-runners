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
}

data "aws_region" "this" {}

module "vpc" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/vpc?ref=0.1.0"

  name       = local.name
  region     = data.aws_region.this.id
  cidr_block = var.cidr_block
  subnets    = var.subnets
}

module "ecs" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/ecs?ref=0.1.0"

  name            = local.name
  cidr_blocks     = [module.vpc.vpc_cidr_block]
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  architecture    = "arm64"
  instance_type   = "m6g.large"
  logging_enabled = true
  aws_region      = data.aws_region.this.id
  tasks = {}
}
