<!-- BEGIN_TF_DOCS -->
# github-actions-runners

End-to-end deployment of self-hosted GitHub Actions runners to do builds on ECS Fargate.

## Features
* Support for secure, cost-efficient conda package builds.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_architecture"></a> [architecture](#input\_architecture) | ECS instance architecture (e.g., arm64, x86\_64) | `string` | n/a | yes |
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | The CIDR block for the VPC. | `string` | n/a | yes |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | CPU units for the container (1024 = 1 vCPU) | `number` | n/a | yes |
| <a name="input_github_app_client_id_param"></a> [github\_app\_client\_id\_param](#input\_github\_app\_client\_id\_param) | SSM parameter name for GitHub App client ID | `string` | n/a | yes |
| <a name="input_github_app_installation_id"></a> [github\_app\_installation\_id](#input\_github\_app\_installation\_id) | GitHub App installation ID to be passed to the runner container | `string` | n/a | yes |
| <a name="input_github_app_private_key_param"></a> [github\_app\_private\_key\_param](#input\_github\_app\_private\_key\_param) | SSM parameter name for GitHub App private key | `string` | n/a | yes |
| <a name="input_github_app_ssm_param_arns"></a> [github\_app\_ssm\_param\_arns](#input\_github\_app\_ssm\_param\_arns) | List of ARNs for GitHub App SSM parameters | `list(string)` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | ECS instance type | `string` | n/a | yes |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory for the container in MiB | `number` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | value | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | value | `string` | n/a | yes |
| <a name="input_repository_names"></a> [repository\_names](#input\_repository\_names) | List of repository names to create webhooks for | `list(string)` | n/a | yes |
| <a name="input_runner_image_tag"></a> [runner\_image\_tag](#input\_runner\_image\_tag) | Tag for the runner Docker image | `string` | n/a | yes |
| <a name="input_stage_name"></a> [stage\_name](#input\_stage\_name) | API Gateway stage name | `string` | `"prod"` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Map of subnet configurations. | <pre>map(object({<br/>    availability_zone = string<br/>    cidr_block        = string<br/>    public            = bool<br/>  }))</pre> | n/a | yes |
| <a name="input_webhook_events"></a> [webhook\_events](#input\_webhook\_events) | List of events that should trigger the webhook | `list(string)` | <pre>[<br/>  "workflow_job"<br/>]</pre> | no |
| <a name="input_webhook_image_tag"></a> [webhook\_image\_tag](#input\_webhook\_image\_tag) | Tag for the webhook Docker image | `string` | n/a | yes |

## Outputs

No outputs.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_api_gateway"></a> [api\_gateway](#module\_api\_gateway) | ./modules/api_gateway | n/a |
| <a name="module_ecs"></a> [ecs](#module\_ecs) | git@github.com:jkim-mlops/terraform-modules.git//modules/ecs | 0.2.0 |
| <a name="module_lambda"></a> [lambda](#module\_lambda) | ./modules/lambda | n/a |
| <a name="module_runner"></a> [runner](#module\_runner) | git@github.com:jkim-mlops/terraform-modules.git//modules/docker | 0.1.2 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | git@github.com:jkim-mlops/terraform-modules.git//modules/vpc | 0.2.0 |
| <a name="module_webhook"></a> [webhook](#module\_webhook) | git@github.com:jkim-mlops/terraform-modules.git//modules/docker | 0.2.0 |

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.27.0 |
| <a name="requirement_docker"></a> [docker](#requirement\_docker) | ~> 3.0 |
| <a name="requirement_github"></a> [github](#requirement\_github) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_github"></a> [github](#provider\_github) | ~> 6.0 |
<!-- END_TF_DOCS -->