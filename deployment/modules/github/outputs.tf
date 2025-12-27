output "webhook_ids" {
  description = "Map of repository names to their webhook IDs"
  value = {
    for repo, webhook in github_repository_webhook.this : repo => webhook.id
  }
}

output "webhook_urls" {
  description = "Map of repository names to their webhook URLs"
  value = {
    for repo, webhook in github_repository_webhook.this : repo => webhook.url
  }
}

output "webhook_secrets" {
  description = "Map of repository names to their generated webhook secrets"
  value = {
    for repo, secret in random_string.this : repo => secret.result
  }
  sensitive = true
}

output "repository_names" {
  description = "List of repositories with webhooks configured"
  value       = var.repository_names
}
