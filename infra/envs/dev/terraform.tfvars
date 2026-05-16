env        = "dev"
aws_region = "us-east-1"
project    = "hello-world"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
azs                  = ["us-east-1a", "us-east-1b"]
# NAT gateway required so EKS nodes in private subnets can reach AWS APIs and ECR.
enable_nat_gateway = true

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
enable_compute       = false
enable_lambda        = false
enable_rds           = false
enable_ecr           = false
enable_networking    = true
enable_eks           = true

# EKS / Cilium
eks_kubernetes_version  = "1.35"
eks_node_instance_types = ["t3.medium"]
eks_node_desired_size   = 2
eks_node_min_size       = 1
eks_node_max_size       = 3
cilium_version          = "1.19.4"

