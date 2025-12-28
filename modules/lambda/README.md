<!-- BEGIN_TF_DOCS -->


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ecs_task_definition_arns"></a> [ecs\_task\_definition\_arns](#input\_ecs\_task\_definition\_arns) | List of ECS task definition ARNs that Lambda can run | `list(string)` | n/a | yes |
| <a name="input_ecs_task_execution_role_arn"></a> [ecs\_task\_execution\_role\_arn](#input\_ecs\_task\_execution\_role\_arn) | ECS task execution role ARN that Lambda can pass | `string` | n/a | yes |
| <a name="input_ecs_task_role_arns"></a> [ecs\_task\_role\_arns](#input\_ecs\_task\_role\_arns) | List of ECS task role ARNs that Lambda can pass | `list(string)` | n/a | yes |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Map of environment variables to pass to the Lambda function | `map(string)` | `{}` | no |
| <a name="input_image_uri"></a> [image\_uri](#input\_image\_uri) | value | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | value | `string` | n/a | yes |
| <a name="input_webhook_secret_length"></a> [webhook\_secret\_length](#input\_webhook\_secret\_length) | Length of the generated webhook secret | `number` | `32` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_lambda"></a> [lambda](#output\_lambda) | The lambda function resource. |
| <a name="output_webhook_secret"></a> [webhook\_secret](#output\_webhook\_secret) | The generated webhook secret |

## Modules

No modules.

## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | n/a |
<!-- END_TF_DOCS -->