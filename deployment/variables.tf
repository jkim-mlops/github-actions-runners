variable "cidr_block" {
  description = "The CIDR block for the VPC."
  type        = string
}

variable "subnets" {
  description = "Map of subnet configurations."
  type = map(object({
    availability_zone = string
    cidr_block        = string
    public            = bool
  }))
}