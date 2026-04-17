# ─── Core ─────────────────────────────────────────────────────────────────────

variable "env" {
  description = "Deployment environment name."
  type        = string
}

variable "project" {
  description = "Project name used as a prefix for all resource names."
  type        = string
}

variable "primary_region" {
  description = "Primary AWS region."
  type        = string
}

variable "secondary_region" {
  description = "Secondary AWS region for multi-region deployments."
  type        = string
}

# ─── Primary region networking ────────────────────────────────────────────────

variable "primary_vpc_cidr" {
  description = "CIDR block for the primary VPC."
  type        = string
}

variable "primary_public_subnet_cidrs" {
  description = "Public subnet CIDRs in the primary region (one per AZ)."
  type        = list(string)
}

variable "primary_private_subnet_cidrs" {
  description = "Private subnet CIDRs in the primary region (one per AZ)."
  type        = list(string)
}

variable "primary_azs" {
  description = "Availability zones in the primary region."
  type        = list(string)
}

# ─── Secondary region networking ──────────────────────────────────────────────

variable "secondary_vpc_cidr" {
  description = "CIDR block for the secondary VPC."
  type        = string
}

variable "secondary_public_subnet_cidrs" {
  description = "Public subnet CIDRs in the secondary region (one per AZ)."
  type        = list(string)
}

variable "secondary_private_subnet_cidrs" {
  description = "Private subnet CIDRs in the secondary region (one per AZ)."
  type        = list(string)
}

variable "secondary_azs" {
  description = "Availability zones in the secondary region."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways so private subnets can reach the internet."
  type        = bool
  default     = true
}

# ─── Compute ──────────────────────────────────────────────────────────────────

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling Groups."
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
  description = "Name of the ECR repository (primary region only)."
  type        = string
}

# ─── Lambda ───────────────────────────────────────────────────────────────────

variable "lambda_function_name" {
  description = "Logical name of the Lambda function (appended to project-env prefix)."
  type        = string
  default     = "processor"
}

# ─── Feature flags ────────────────────────────────────────────────────────────

variable "enable_load_balancer" {
  description = "Create Application Load Balancers in both regions."
  type        = bool
  default     = false
}

variable "enable_compute" {
  description = "Create EC2 Auto Scaling Groups in both regions."
  type        = bool
  default     = false
}

variable "enable_lambda" {
  description = "Create Lambda functions in both regions."
  type        = bool
  default     = false
}

variable "enable_rds" {
  description = "Create the RDS PostgreSQL instance (primary region only)."
  type        = bool
  default     = false
}

variable "enable_ecr" {
  description = "Create the ECR repository (primary region only)."
  type        = bool
  default     = false
}
