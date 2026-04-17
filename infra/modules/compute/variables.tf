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

variable "subnet_ids" {
  description = "Subnet IDs for EC2 instances"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB — grants inbound access to EC2 (empty string disables ALB ingress rule)"
  type        = string
  default     = ""
}

variable "target_group_arns" {
  description = "ALB target group ARNs to attach the ASG to"
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Port the application listens on"
  type        = number
  default     = 80
}

variable "min_size" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances"
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Desired number of instances"
  type        = number
  default     = 1
}

variable "user_data" {
  description = "User data script (raw text — will be base64-encoded)"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "EC2 key pair name (optional — prefer SSM Session Manager)"
  type        = string
  default     = null
}
