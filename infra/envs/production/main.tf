# production: multi-region AWS (us-east-1 primary + us-west-2 secondary).
# All resources must have deletion_protection / prevent_destroy = true.

# ─── Networking ───────────────────────────────────────────────────────────────

module "networking_primary" {
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
  vpc_id            = module.networking_primary.vpc_id
  public_subnet_ids = module.networking_primary.public_subnet_ids
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
  vpc_id            = module.networking_secondary.vpc_id
  public_subnet_ids = module.networking_secondary.public_subnet_ids
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
  vpc_id                = module.networking_primary.vpc_id
  subnet_ids            = module.networking_primary.private_subnet_ids
  instance_type         = var.instance_type
  app_port              = var.app_port
  alb_security_group_id = var.enable_load_balancer ? module.load_balancer_primary[0].security_group_id : ""
  target_group_arns     = var.enable_load_balancer ? [module.load_balancer_primary[0].target_group_arn] : []
  min_size              = 2
  max_size              = 6
  desired_capacity      = 2
}

module "compute_secondary" {
  count  = var.enable_compute ? 1 : 0
  source = "../../modules/compute"
  providers = {
    aws = aws.secondary
  }

  project               = var.project
  env                   = "${var.env}-secondary"
  vpc_id                = module.networking_secondary.vpc_id
  subnet_ids            = module.networking_secondary.private_subnet_ids
  instance_type         = var.instance_type
  app_port              = var.app_port
  alb_security_group_id = var.enable_load_balancer ? module.load_balancer_secondary[0].security_group_id : ""
  target_group_arns     = var.enable_load_balancer ? [module.load_balancer_secondary[0].target_group_arn] : []
  min_size              = 2
  max_size              = 6
  desired_capacity      = 2
}

# ─── DynamoDB ───────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "items_primary" {
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

# ─── SQS ───────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "processor_primary" {
  provider = aws.primary
  name     = var.sqs_queue_name

  tags = {
    Name = var.sqs_queue_name
  }
}

resource "aws_sqs_queue" "processor_secondary" {
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
    TABLE_NAME = aws_dynamodb_table.items_primary.name
  }

  dynamodb_table_arn      = aws_dynamodb_table.items_primary.arn
  sqs_queue_arn           = aws_sqs_queue.processor_primary.arn
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
    TABLE_NAME = aws_dynamodb_table.items_secondary.name
  }

  dynamodb_table_arn      = aws_dynamodb_table.items_secondary.arn
  sqs_queue_arn           = aws_sqs_queue.processor_secondary.arn
  deployment_package_path = var.deployment_package_path
}

# ─── RDS (PostgreSQL, Multi-AZ, primary only) ────────────────────────────────

module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "../../modules/rds"
  providers = {
    aws = aws.primary
  }

  project    = var.project
  env        = var.env
  vpc_id     = module.networking_primary.vpc_id
  subnet_ids = module.networking_primary.private_subnet_ids
  db_name    = var.db_name
  username   = var.db_username

  allowed_security_group_ids = var.enable_compute ? [module.compute_primary[0].security_group_id] : []

  instance_class          = "db.t3.micro"
  multi_az                = true  # HA for production
  skip_final_snapshot     = false # retain snapshot on destroy
  deletion_protection     = true  # guard against accidental deletion
  backup_retention_period = 14
}

# ─── ECR (primary region only) ────────────────────────────────────────────────

module "ecr" {
  count  = var.enable_ecr ? 1 : 0
  source = "../../modules/ecr"
  providers = {
    aws = aws.primary
  }

  project              = var.project
  env                  = var.env
  repository_name      = var.ecr_repo_name
  image_tag_mutability = "IMMUTABLE" # prevent tag overwriting in production
  max_image_count      = 20
}
