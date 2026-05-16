provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.env
      ManagedBy   = "terraform"
    }
  }
}

# ─── Helm provider (used when enable_eks = true) ──────────────────────────────
# On the very first apply, run:  terraform apply -target=module.eks
# Subsequent applies can run normally once the cluster endpoint is available.

provider "helm" {
  kubernetes = {
    host                   = try(module.eks[0].cluster_endpoint, "https://localhost:6443")
    cluster_ca_certificate = try(base64decode(module.eks[0].cluster_ca_data), "")

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", try(module.eks[0].cluster_name, ""),
        "--region", var.aws_region,
      ]
    }
  }
}
