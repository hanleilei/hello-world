# ─── Networking ───────────────────────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  project              = var.project
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs
  enable_nat_gateway   = var.enable_nat_gateway
}

# ─── Load Balancer ────────────────────────────────────────────────────────────

module "load_balancer" {
  count  = var.enable_load_balancer ? 1 : 0
  source = "../../modules/load-balancer"

  project           = var.project
  env               = var.env
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  target_port       = var.app_port
}

# ─── Compute (EC2 + ASG) ──────────────────────────────────────────────────────

module "compute" {
  count  = var.enable_compute ? 1 : 0
  source = "../../modules/compute"

  project               = var.project
  env                   = var.env
  vpc_id                = module.networking.vpc_id
  subnet_ids            = module.networking.private_subnet_ids
  instance_type         = var.instance_type
  app_port              = var.app_port
  alb_security_group_id = var.enable_load_balancer ? module.load_balancer[0].security_group_id : ""
  target_group_arns     = var.enable_load_balancer ? [module.load_balancer[0].target_group_arn] : []
  min_size              = 1
  max_size              = 2
  desired_capacity      = 1
}

# ─── Lambda ───────────────────────────────────────────────────────────────────

module "lambda" {
  count  = var.enable_lambda ? 1 : 0
  source = "../../modules/lambda"

  project       = var.project
  env           = var.env
  function_name = var.lambda_function_name
}

# ─── RDS (PostgreSQL) ─────────────────────────────────────────────────────────

module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "../../modules/rds"

  project    = var.project
  env        = var.env
  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
  db_name    = var.db_name
  username   = var.db_username

  allowed_security_group_ids = var.enable_compute ? [module.compute[0].security_group_id] : []

  instance_class          = "db.t3.micro"
  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 1
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

module "ecr" {
  count  = var.enable_ecr ? 1 : 0
  source = "../../modules/ecr"

  project         = var.project
  env             = var.env
  repository_name = var.ecr_repo_name
}
