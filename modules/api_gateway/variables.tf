variable "name" {
  description = "Name for the API Gateway"
  type        = string
}

variable "stage_name" {
  description = "Stage name for the API Gateway deployment"
  type        = string
  default     = "prod"
}

variable "lambda" {
  description = "Lambda function object"
  type = object({
    invoke_arn    = string
    function_name = string
  })
}
