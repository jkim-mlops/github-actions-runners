<!-- BEGIN_TF_DOCS -->
# deployment

End-to-end deployment of Github Actions runners.

## Features
* Support for secure, cost-efficient container builds with **kaniko**.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | The CIDR block for the VPC. | `string` | n/a | yes |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Map of subnet configurations. | <pre>map(object({<br/>    availability_zone = string<br/>    cidr_block        = string<br/>    public            = bool<br/>  }))</pre> | n/a | yes |

## Outputs

No outputs.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_docker"></a> [docker](#module\_docker) | git@github.com:jkim-mlops/terraform-modules.git//modules/docker | 0.1.0 |
| <a name="module_ecs"></a> [ecs](#module\_ecs) | git@github.com:jkim-mlops/terraform-modules.git//modules/ecs | 0.1.0 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | git@github.com:jkim-mlops/terraform-modules.git//modules/vpc | 0.1.0 |

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.27.0 |
| <a name="requirement_docker"></a> [docker](#requirement\_docker) | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.27.0 |
<!-- END_TF_DOCS -->