<!-- BEGIN_TF_DOCS -->


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_lambda"></a> [lambda](#input\_lambda) | Lambda function object | <pre>object({<br/>    invoke_arn    = string<br/>    function_name = string<br/>  })</pre> | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name for the API Gateway | `string` | n/a | yes |
| <a name="input_stage_name"></a> [stage\_name](#input\_stage\_name) | Stage name for the API Gateway deployment | `string` | `"prod"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api_endpoint"></a> [api\_endpoint](#output\_api\_endpoint) | API Gateway endpoint URL |
| <a name="output_rest_api_id"></a> [rest\_api\_id](#output\_rest\_api\_id) | API Gateway REST API ID |
| <a name="output_stage_name"></a> [stage\_name](#output\_stage\_name) | API Gateway stage name |
| <a name="output_webhook_url"></a> [webhook\_url](#output\_webhook\_url) | Full webhook URL |

## Modules

No modules.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 4.0 |
<!-- END_TF_DOCS -->