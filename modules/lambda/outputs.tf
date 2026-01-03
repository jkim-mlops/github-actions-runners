output "lambda" {
  description = "The lambda function resource."
  value       = aws_lambda_function.this
}

output "webhook_secret" {
  description = "The generated webhook secret"
  value       = random_string.webhook_secret.result
  sensitive   = true
}