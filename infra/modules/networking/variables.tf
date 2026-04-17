variable "project" {
  description = "Project name used as a resource prefix"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one entry per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — one entry per AZ"
  type        = list(string)
}

variable "azs" {
  description = "Availability zones — must align with subnet_cidr lists"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Provision a single NAT gateway for private subnet egress (incurs cost)"
  type        = bool
  default     = false
}
