<!-- BEGIN_TF_DOCS -->
# Lambda Webhook Handler Module

Creates a Lambda function to handle GitHub webhook events and trigger ECS tasks for self-hosted runners.

## Features
* Generates secure webhook secret
* IAM roles with ECS task execution permissions
* Container-based Lambda function
* Environment variable configuration support

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_architectures"></a> [architectures](#input\_architectures) | Architectures for the Lambda function (e.g., ["arm64"], ["x86\_64"]) | `list(string)` | <pre>[<br/>  "arm64"<br/>]</pre> | no |
| <a name="input_ecs_task_definition_arns"></a> [ecs\_task\_definition\_arns](#input\_ecs\_task\_definition\_arns) | List of ECS task definition ARNs that Lambda can run | `list(string)` | n/a | yes |
| <a name="input_ecs_task_execution_role_arn"></a> [ecs\_task\_execution\_role\_arn](#input\_ecs\_task\_execution\_role\_arn) | ECS task execution role ARN that Lambda can pass | `string` | n/a | yes |
| <a name="input_ecs_task_role_arns"></a> [ecs\_task\_role\_arns](#input\_ecs\_task\_role\_arns) | List of ECS task role ARNs that Lambda can pass | `list(string)` | n/a | yes |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Map of environment variables to pass to the Lambda function | `map(string)` | `{}` | no |
| <a name="input_image_uri"></a> [image\_uri](#input\_image\_uri) | value | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | value | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for Lambda security group. | `string` | n/a | yes |
| <a name="input_vpc_subnet_ids"></a> [vpc\_subnet\_ids](#input\_vpc\_subnet\_ids) | List of subnet IDs for Lambda VPC config. | `list(string)` | `[]` | no |
| <a name="input_webhook_secret_length"></a> [webhook\_secret\_length](#input\_webhook\_secret\_length) | Length of the generated webhook secret | `number` | `32` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_lambda"></a> [lambda](#output\_lambda) | The lambda function resource. |
| <a name="output_webhook_secret"></a> [webhook\_secret](#output\_webhook\_secret) | The generated webhook secret |

## Modules

No modules.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |
<!-- END_TF_DOCS -->