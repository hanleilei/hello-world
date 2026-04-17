# Shared variable declarations referenced by every environment.
# Each environment's terraform.tfvars provides the concrete values.

variable "env" {
  description = "Environment name: dev | test | perf | staging | production"
  type        = string

  validation {
    condition     = contains(["dev", "test", "perf", "staging", "production"], var.env)
    error_message = "env must be one of: dev, test, perf, staging, production."
  }
}

variable "aws_region" {
  description = "AWS region for this environment"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used as a resource prefix"
  type        = string
  default     = "hello-world"
}
