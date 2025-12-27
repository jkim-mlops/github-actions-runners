# Retrieve GitHub token from SSM Parameter Store
data "aws_ssm_parameter" "github_token" {
  name            = var.github_token_param
  with_decryption = true
}

# Create webhook for repository
resource "github_repository_webhook" "this" {
  repository = var.repository_name
  active     = var.webhook_active

  configuration {
    url          = var.webhook_url
    content_type = var.webhook_content_type
    secret       = var.webhook_secret
    insecure_ssl = false
  }

  events = var.webhook_events
}
