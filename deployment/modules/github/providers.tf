provider "github" {
  token = data.aws_ssm_parameter.github_token.value
  owner = var.github_owner
}
