variable "github_token_param" {
  description = "AWS SSM Parameter name containing the GitHub personal access token"
  type        = string
}

variable "github_owner" {
  description = "GitHub organization or user name"
  type        = string
}

variable "repository_names" {
  description = "List of repository names to create webhooks for"
  type        = list(string)
}

variable "webhook_url" {
  description = "The webhook endpoint URL"
  type        = string
}

variable "webhook_content_type" {
  description = "The content type for the webhook payload"
  type        = string
  default     = "json"
}

variable "webhook_events" {
  description = "List of events that should trigger the webhook"
  type        = list(string)
  default     = ["push", "pull_request"]
}

variable "webhook_active" {
  description = "Whether the webhook should be active"
  type        = bool
  default     = true
}

variable "secret_length" {
  description = "Length of the generated webhook secret"
  type        = number
  default     = 32
}
