# ─── Core ─────────────────────────────────────────────────────────────────────

variable "env" {
  description = "Deployment environment name."
  type        = string
}

variable "project" {
  description = "Project name used as a prefix for all resource names."
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (one per AZ)."
  type        = list(string)
}

variable "azs" {
  description = "Availability zones to spread subnets across."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway so private subnets can reach the internet."
  type        = bool
  default     = false
}

# ─── Compute ──────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling Group."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the application listens on (used by ALB and security groups)."
  type        = number
  default     = 80
}

# ─── RDS ──────────────────────────────────────────────────────────────────────

variable "db_name" {
  description = "Initial database name created on the RDS instance."
  type        = string
}

variable "db_username" {
  description = "Master username for the RDS instance."
  type        = string
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

variable "ecr_repo_name" {
  description = "Name of the ECR repository."
  type        = string
}

# ─── Lambda ───────────────────────────────────────────────────────────────────

variable "sqs_queue_name" {
  description = "Name of the SQS queue for async processing."
  type        = string
  default     = "processor"
}

variable "deployment_package_path" {
  description = "Local path to the Chalice deployment ZIP. Set by service-cd pipeline; leave empty for infra-only runs."
  type        = string
  default     = ""
}

# ─── Feature flags ────────────────────────────────────────────────────────────

variable "enable_load_balancer" {
  description = "Create the Application Load Balancer and related resources."
  type        = bool
  default     = false
}

variable "enable_compute" {
  description = "Create the EC2 Auto Scaling Group and related resources."
  type        = bool
  default     = false
}

variable "enable_lambda" {
  description = "Create the Lambda function and related resources."
  type        = bool
  default     = false
}

variable "enable_rds" {
  description = "Create the RDS PostgreSQL instance and related resources."
  type        = bool
  default     = false
}

variable "enable_ecr" {
  description = "Create the ECR repository."
  type        = bool
  default     = false
}
