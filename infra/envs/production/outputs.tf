output "alb_dns_name_primary" {
  description = "Primary ALB DNS name."
  value       = var.enable_load_balancer ? module.load_balancer_primary[0].alb_dns_name : null
}

output "alb_dns_name_secondary" {
  description = "Secondary ALB DNS name."
  value       = var.enable_load_balancer ? module.load_balancer_secondary[0].alb_dns_name : null
}

output "ecr_repository_url" {
  description = "ECR repository URL (primary region)."
  value       = var.enable_ecr ? module.ecr[0].repository_url : null
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN containing RDS credentials."
  value       = var.enable_rds ? module.rds[0].secret_arn : null
  sensitive   = true
}
