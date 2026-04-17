env     = "staging"
project = "hello-world"

primary_region   = "us-east-1"
secondary_region = "us-west-2"

# Primary region (us-east-1) — 3-AZ deployment
primary_vpc_cidr             = "10.4.0.0/16"
primary_public_subnet_cidrs  = ["10.4.0.0/24", "10.4.1.0/24", "10.4.2.0/24"]
primary_private_subnet_cidrs = ["10.4.10.0/24", "10.4.11.0/24", "10.4.12.0/24"]
primary_azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Secondary region (us-west-2) — 3-AZ deployment
secondary_vpc_cidr             = "10.5.0.0/16"
secondary_public_subnet_cidrs  = ["10.5.0.0/24", "10.5.1.0/24", "10.5.2.0/24"]
secondary_private_subnet_cidrs = ["10.5.10.0/24", "10.5.11.0/24", "10.5.12.0/24"]
secondary_azs                  = ["us-west-2a", "us-west-2b", "us-west-2c"]

enable_nat_gateway = true

# Compute
instance_type = "t3.micro"
app_port      = 80

# RDS
db_name     = "helloworld"
db_username = "admin"

# ECR
ecr_repo_name = "hello-world-staging"

# Lambda
lambda_function_name = "processor"

# Feature flags
enable_load_balancer = false
enable_compute       = false
enable_lambda        = false
enable_rds           = false
enable_ecr           = false
