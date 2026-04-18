# perf mirrors production sizing to give accurate load-test results.
# Deployed to two AWS regions for realistic cross-region latency measurement.

# ─── Networking ───────────────────────────────────────────────────────────────

module "networking_primary" {
  count  = var.enable_networking ? 1 : 0
  source = "../../modules/networking"
  providers = {
    aws = aws.primary
  }

  project              = var.project
  env                  = var.env
  vpc_cidr             = var.primary_vpc_cidr
  public_subnet_cidrs  = var.primary_public_subnet_cidrs
  private_subnet_cidrs = var.primary_private_subnet_cidrs
  azs                  = var.primary_azs
  enable_nat_gateway   = var.enable_nat_gateway
}

module "networking_secondary" {
  count  = var.enable_networking ? 1 : 0
  source = "../../modules/networking"
  providers = {
    aws = aws.secondary
  }

  project              = var.project
  env                  = var.env
  vpc_cidr             = var.secondary_vpc_cidr
  public_subnet_cidrs  = var.secondary_public_subnet_cidrs
  private_subnet_cidrs = var.secondary_private_subnet_cidrs
  azs                  = var.secondary_azs
  enable_nat_gateway   = var.enable_nat_gateway
}

# ─── Load Balancer ────────────────────────────────────────────────────────────

module "load_balancer_primary" {
  count  = var.enable_load_balancer ? 1 : 0
  source = "../../modules/load-balancer"
  providers = {
    aws = aws.primary
  }

  project           = var.project
  env               = "${var.env}-primary"
  vpc_id            = try(module.networking_primary[0].vpc_id, "")
  public_subnet_ids = try(module.networking_primary[0].public_subnet_ids, [])
  target_port       = var.app_port
}

module "load_balancer_secondary" {
  count  = var.enable_load_balancer ? 1 : 0
  source = "../../modules/load-balancer"
  providers = {
    aws = aws.secondary
  }

  project           = var.project
  env               = "${var.env}-secondary"
  vpc_id            = try(module.networking_secondary[0].vpc_id, "")
  public_subnet_ids = try(module.networking_secondary[0].public_subnet_ids, [])
  target_port       = var.app_port
}

# ─── Compute (EC2 + ASG) ──────────────────────────────────────────────────────

module "compute_primary" {
  count  = var.enable_compute ? 1 : 0
  source = "../../modules/compute"
  providers = {
    aws = aws.primary
  }

  project               = var.project
  env                   = "${var.env}-primary"
  vpc_id                = try(module.networking_primary[0].vpc_id, "")
  subnet_ids            = try(module.networking_primary[0].private_subnet_ids, [])
  instance_type         = var.instance_type
  app_port              = var.app_port
  alb_security_group_id = var.enable_load_balancer ? module.load_balancer_primary[0].security_group_id : ""
  target_group_arns     = var.enable_load_balancer ? [module.load_balancer_primary[0].target_group_arn] : []
  min_size              = 1
  max_size              = 3
  desired_capacity      = 1
}

module "compute_secondary" {
  count  = var.enable_compute ? 1 : 0
  source = "../../modules/compute"
  providers = {
    aws = aws.secondary
  }

  project               = var.project
  env                   = "${var.env}-secondary"
  vpc_id                = try(module.networking_secondary[0].vpc_id, "")
  subnet_ids            = try(module.networking_secondary[0].private_subnet_ids, [])
  instance_type         = var.instance_type
  app_port              = var.app_port
  alb_security_group_id = var.enable_load_balancer ? module.load_balancer_secondary[0].security_group_id : ""
  target_group_arns     = var.enable_load_balancer ? [module.load_balancer_secondary[0].target_group_arn] : []
  min_size              = 1
  max_size              = 3
  desired_capacity      = 1
}

# ─── DynamoDB ─────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "items_primary" {
  count        = var.enable_lambda ? 1 : 0
  provider     = aws.primary
  name         = "${var.project}-items-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "${var.project}-items-${var.env}-primary"
  }
}

resource "aws_dynamodb_table" "items_secondary" {
  count        = var.enable_lambda ? 1 : 0
  provider     = aws.secondary
  name         = "${var.project}-items-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "${var.project}-items-${var.env}-secondary"
  }
}

# ─── SQS ──────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "processor_primary" {
  count    = var.enable_lambda ? 1 : 0
  provider = aws.primary
  name     = var.sqs_queue_name

  tags = {
    Name = var.sqs_queue_name
  }
}

resource "aws_sqs_queue" "processor_secondary" {
  count    = var.enable_lambda ? 1 : 0
  provider = aws.secondary
  name     = var.sqs_queue_name

  tags = {
    Name = var.sqs_queue_name
  }
}

# ─── Lambda ───────────────────────────────────────────────────────────────────

module "lambda_primary" {
  count  = var.enable_lambda ? 1 : 0
  source = "../../modules/lambda"
  providers = {
    aws = aws.primary
  }

  project = var.project
  env     = "${var.env}-primary"

  environment_variables = {
    ENV        = var.env
    TABLE_NAME = aws_dynamodb_table.items_primary[0].name
  }

  dynamodb_table_arn      = aws_dynamodb_table.items_primary[0].arn
  sqs_queue_arn           = aws_sqs_queue.processor_primary[0].arn
  deployment_package_path = var.deployment_package_path
}

module "lambda_secondary" {
  count  = var.enable_lambda ? 1 : 0
  source = "../../modules/lambda"
  providers = {
    aws = aws.secondary
  }

  project = var.project
  env     = "${var.env}-secondary"

  environment_variables = {
    ENV        = var.env
    TABLE_NAME = aws_dynamodb_table.items_secondary[0].name
  }

  dynamodb_table_arn      = aws_dynamodb_table.items_secondary[0].arn
  sqs_queue_arn           = aws_sqs_queue.processor_secondary[0].arn
  deployment_package_path = var.deployment_package_path
}

# ─── RDS (PostgreSQL, primary only) ──────────────────────────────────────────

module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "../../modules/rds"
  providers = {
    aws = aws.primary
  }

  project    = var.project
  env        = var.env
  vpc_id     = try(module.networking_primary[0].vpc_id, "")
  subnet_ids = try(module.networking_primary[0].private_subnet_ids, [])
  db_name    = var.db_name
  username   = var.db_username

  allowed_security_group_ids = var.enable_compute ? [module.compute_primary[0].security_group_id] : []

  instance_class          = "db.t3.micro"
  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 7
}

# ─── ECR (primary region only) ────────────────────────────────────────────────

module "ecr" {
  count  = var.enable_ecr ? 1 : 0
  source = "../../modules/ecr"
  providers = {
    aws = aws.primary
  }

  project         = var.project
  env             = var.env
  repository_name = var.ecr_repo_name
}
