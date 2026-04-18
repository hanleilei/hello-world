env        = "dev"
aws_region = "us-east-1"
project    = "hello-world"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
azs                  = ["us-east-1a", "us-east-1b"]
# NAT gateway disabled in dev to reduce cost.
enable_nat_gateway = false

# Compute — t3.micro keeps dev within free-tier / minimal cost.
instance_type = "t3.micro"
app_port      = 80

# RDS
db_name     = "helloworld"
db_username = "admin"

# ECR
ecr_repo_name = "hello-world"

# Lambda
sqs_queue_name = "processor"

# Feature flags
enable_load_balancer = true
enable_compute       = true
enable_lambda        = true
enable_rds           = false
enable_ecr           = true
enable_networking    = true
