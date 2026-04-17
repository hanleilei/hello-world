output "alb_dns_name" {
  description = "ALB DNS name — application entry point."
  value       = var.enable_load_balancer ? module.load_balancer[0].alb_dns_name : null
}

output "ecr_repository_url" {
  description = "ECR repository URL for docker push."
  value       = var.enable_ecr ? module.ecr[0].repository_url : null
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN containing RDS credentials."
  value       = var.enable_rds ? module.rds[0].secret_arn : null
  sensitive   = true
}
