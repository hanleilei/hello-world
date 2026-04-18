env        = "test"
aws_region = "us-east-1"
project    = "hello-world"

vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
azs                  = ["us-east-1a", "us-east-1b"]
# NAT gateway disabled in test to reduce cost.
enable_nat_gateway = false

# Compute
instance_type = "t3.micro"
app_port      = 80

# RDS
db_name     = "helloworld"
db_username = "admin"

# ECR
ecr_repo_name = "hello-world-test"

# Lambda
sqs_queue_name = "processor"

# Feature flags
enable_load_balancer = false
enable_compute       = false
enable_lambda        = false
enable_rds           = false
enable_ecr           = false
