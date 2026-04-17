variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "repository_name" {
  description = "ECR repository name"
  type        = string
}

variable "image_tag_mutability" {
  description = "Tag mutability: MUTABLE or IMMUTABLE (use IMMUTABLE in production)"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Enable automated image vulnerability scanning on push"
  type        = bool
  default     = true
}

variable "max_image_count" {
  description = "Maximum number of images to retain (lifecycle policy)"
  type        = number
  default     = 10
}

