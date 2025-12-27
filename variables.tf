variable "architecture" {
  description = "ECS instance architecture (e.g., arm64, x86_64)"
  type        = string
}

variable "cidr_block" {
  description = "The CIDR block for the VPC."
  type        = string
}

variable "cpu" {
  description = "CPU units for the container (1024 = 1 vCPU)"
  type        = number
}

variable "github_app_client_id_param_name" {
  description = "SSM parameter name for GitHub App client ID"
  type        = string
}

variable "github_app_private_key_param_name" {
  description = "SSM parameter name for GitHub App private key"
  type        = string
}

variable "github_app_ssm_param_arns" {
  description = "List of ARNs for GitHub App SSM parameters"
  type        = list(string)
}

variable "instance_type" {
  description = "ECS instance type"
  type        = string
}

variable "memory" {
  description = "Memory for the container in MiB"
  type        = number
}

variable "name" { 
  description = "value"
  type = string
}

variable "region" {
  description = "value"
  type = string
}

variable "subnets" {
  description = "Map of subnet configurations."
  type = map(object({
    availability_zone = string
    cidr_block        = string
    public            = bool
  }))
}