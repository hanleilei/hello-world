variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "internal" {
  description = "Whether the ALB is internal (private)"
  type        = bool
  default     = false
}

variable "target_port" {
  description = "Port on which EC2 targets receive traffic"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "deregistration_delay" {
  description = "Seconds to wait before deregistering a target"
  type        = number
  default     = 30
}
