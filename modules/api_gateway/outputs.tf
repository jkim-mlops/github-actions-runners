output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "webhook_url" {
  description = "Full webhook URL"
  value       = "${aws_api_gateway_stage.this.invoke_url}/webhook"
}

output "rest_api_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.this.id
}

output "stage_name" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.this.stage_name
}
