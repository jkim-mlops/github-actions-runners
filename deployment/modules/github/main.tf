# Retrieve GitHub token from SSM Parameter Store
data "aws_ssm_parameter" "github_token" {
  name            = var.github_token_param
  with_decryption = true
}

# Generate a random alphanumeric secret for each repository
resource "random_string" "this" {
  for_each = toset(var.repository_names)

  length  = var.secret_length
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# Create webhook for each repository
resource "github_repository_webhook" "this" {
  for_each = toset(var.repository_names)

  repository = each.value
  active     = var.webhook_active

  configuration {
    url          = var.webhook_url
    content_type = var.webhook_content_type
    secret       = random_string.this[each.key].result
    insecure_ssl = false
  }

  events = var.webhook_events
}
