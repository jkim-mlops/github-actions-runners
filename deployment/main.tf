data "aws_region" "this" {}

module "vpc" {
  source = "git@github.com:jkim-mlops/terraform-modules.git//modules/vpc?ref=0.1.0"

  name       = var.name
  region     = data.aws_region.this.id
  cidr_block = var.cidr_block
  subnets    = var.subnets
}
