output "api_endpoint_url" {
  description = "API Gateway base invoke URL for the Lambda API handler."
  value       = var.enable_lambda ? module.lambda[0].api_endpoint_url : null
}

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

output "eks_cluster_name" {
  description = "EKS cluster name."
  value       = var.enable_eks ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = var.enable_eks ? module.eks[0].cluster_endpoint : null
}

output "eks_oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = var.enable_eks ? module.eks[0].oidc_provider_arn : null
}
