output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (used to configure IRSA)."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for IRSA."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_role_arn" {
  description = "ARN of the IAM role attached to the managed node group."
  value       = aws_iam_role.node_group.arn
}

output "cluster_security_group_id" {
  description = "ID of the additional security group attached to the EKS control plane."
  value       = aws_security_group.cluster.id
}
