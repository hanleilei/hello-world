# ─── Master Password ──────────────────────────────────────────────────────────

resource "random_password" "master" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ─── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.env}-rds-sg"
  description = "Allow PostgreSQL inbound from permitted security groups only"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    iterator = sg
    content {
      description     = "PostgreSQL from ${sg.value}"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [sg.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${var.env}-rds-sg"
  }
}

# ─── DB Subnet Group ──────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-${var.env}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project}-${var.env}-db-subnet-group"
  }
}

# ─── RDS Instance ─────────────────────────────────────────────────────────────

resource "aws_db_instance" "this" {
  identifier = "${var.project}-${var.env}-postgres"

  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = var.multi_az
  publicly_accessible = false
  deletion_protection = var.deletion_protection

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.project}-${var.env}-final-snapshot"

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Disable extra-cost features for lower environments.
  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name = "${var.project}-${var.env}-postgres"
  }
}

# ─── Credentials in Secrets Manager ──────────────────────────────────────────

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/${var.env}/rds/master"
  description             = "RDS master credentials for ${var.project}-${var.env}"
  recovery_window_in_days = 0 # increase to 7-30 for production

  tags = {
    Name = "${var.project}-${var.env}-rds-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.master.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.db_name
  })
}

