variable "vpc_subnet_ids" {
  description = "List of subnet IDs for Lambda VPC config."
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID for Lambda security group."
  type        = string
  default     = ""
}
variable "name" {
  description = "value"
  type        = string
}

variable "image_uri" {
  description = "value"
  type        = string
}

variable "ecs_task_definition_arns" {
  description = "List of ECS task definition ARNs that Lambda can run"
  type        = list(string)
}

variable "ecs_task_execution_role_arn" {
  description = "ECS task execution role ARN that Lambda can pass"
  type        = string
}

variable "ecs_task_role_arns" {
  description = "List of ECS task role ARNs that Lambda can pass"
  type        = list(string)
}

variable "environment_variables" {
  description = "Map of environment variables to pass to the Lambda function"
  type        = map(string)
  default     = {}
}

variable "architectures" {
  description = "Architectures for the Lambda function (e.g., [\"arm64\"], [\"x86_64\"])"
  type        = list(string)
  default     = ["arm64"]
}

variable "webhook_secret_length" {
  description = "Length of the generated webhook secret"
  type        = number
  default     = 32
}