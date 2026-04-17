env     = "production"
project = "hello-world"

primary_region   = "us-east-1"
secondary_region = "us-west-2"

# Primary region (us-east-1) — 3-AZ deployment
primary_vpc_cidr             = "10.6.0.0/16"
primary_public_subnet_cidrs  = ["10.6.0.0/24", "10.6.1.0/24", "10.6.2.0/24"]
primary_private_subnet_cidrs = ["10.6.10.0/24", "10.6.11.0/24", "10.6.12.0/24"]
primary_azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Secondary region (us-west-2) — 3-AZ deployment
secondary_vpc_cidr             = "10.7.0.0/16"
secondary_public_subnet_cidrs  = ["10.7.0.0/24", "10.7.1.0/24", "10.7.2.0/24"]
secondary_private_subnet_cidrs = ["10.7.10.0/24", "10.7.11.0/24", "10.7.12.0/24"]
secondary_azs                  = ["us-west-2a", "us-west-2b", "us-west-2c"]

enable_nat_gateway = true

# Compute — t3.small for production workloads
instance_type = "t3.small"
app_port      = 80

# RDS
db_name     = "helloworld"
db_username = "admin"

# ECR
ecr_repo_name = "hello-world"

# Lambda
lambda_function_name = "processor"

# Feature flags
enable_load_balancer = false
enable_compute       = false
enable_lambda        = false
enable_rds           = false
enable_ecr           = false
