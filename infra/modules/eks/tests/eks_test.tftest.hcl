# Uses Terraform's built-in test framework (requires terraform >= 1.10).
# Run with: make test MODULE=eks  (from repo root)
#
# mock_provider avoids the need for real AWS credentials in CI.

mock_provider "aws" {}
mock_provider "tls" {}

# ─── Test 1: Basic EKS cluster plan ───────────────────────────────────────────

run "basic_cluster_plan" {
  command = plan

  variables {
    project = "hello-world"
    env     = "dev"
    vpc_id  = "vpc-0123456789abcdef0"
    subnet_ids = [
      "subnet-0123456789abcdef0",
      "subnet-0123456789abcdef1",
    ]
    public_subnet_ids = [
      "subnet-0123456789abcdef0",
      "subnet-0123456789abcdef1",
    ]
    private_subnet_ids = [
      "subnet-0123456789abcdef2",
      "subnet-0123456789abcdef3",
    ]
    kubernetes_version  = "1.35"
    node_instance_types = ["t3.medium"]
    node_desired_size   = 2
    node_min_size       = 1
    node_max_size       = 3
  }

  assert {
    condition     = aws_eks_cluster.this.name == "hello-world-dev-eks"
    error_message = "Cluster name should be hello-world-dev-eks"
  }

  assert {
    condition     = aws_eks_cluster.this.version == "1.35"
    error_message = "Cluster version should be 1.35"
  }

  assert {
    condition     = aws_iam_role.eks_cluster.name == "hello-world-dev-eks-cluster-role"
    error_message = "Cluster IAM role name is incorrect"
  }

  assert {
    condition     = aws_iam_role.node_group.name == "hello-world-dev-eks-node-role"
    error_message = "Node group IAM role name is incorrect"
  }

  assert {
    condition     = aws_eks_node_group.this.cluster_name == aws_eks_cluster.this.name
    error_message = "Node group should be attached to the cluster"
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].desired_size == 2
    error_message = "Node group desired size should be 2"
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].min_size == 1
    error_message = "Node group min size should be 1"
  }

  assert {
    condition     = aws_eks_node_group.this.scaling_config[0].max_size == 3
    error_message = "Node group max size should be 3"
  }
}

# ─── Test 2: Public endpoint disabled ─────────────────────────────────────────

run "private_cluster_plan" {
  command = plan

  variables {
    project = "hello-world"
    env     = "staging"
    vpc_id  = "vpc-0123456789abcdef0"
    subnet_ids = [
      "subnet-0123456789abcdef0",
      "subnet-0123456789abcdef1",
    ]
    public_subnet_ids = []
    private_subnet_ids = [
      "subnet-0123456789abcdef0",
      "subnet-0123456789abcdef1",
    ]
    endpoint_public_access = false
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "Public endpoint access should be disabled"
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true
    error_message = "Private endpoint access should always be enabled"
  }
}

# ─── Test 3: Subnet tags are applied ──────────────────────────────────────────

run "subnet_tags_plan" {
  command = plan

  variables {
    project            = "hello-world"
    env                = "dev"
    vpc_id             = "vpc-0123456789abcdef0"
    subnet_ids         = ["subnet-private-0", "subnet-private-1"]
    public_subnet_ids  = ["subnet-public-0", "subnet-public-1"]
    private_subnet_ids = ["subnet-private-0", "subnet-private-1"]
  }

  assert {
    condition     = length(aws_ec2_tag.private_subnet_internal_elb) == 2
    error_message = "Expected internal-elb tag on 2 private subnets"
  }

  assert {
    condition     = length(aws_ec2_tag.public_subnet_elb) == 2
    error_message = "Expected elb tag on 2 public subnets"
  }

  assert {
    condition     = length(aws_ec2_tag.private_subnet_cluster) == 2
    error_message = "Expected cluster tag on 2 private subnets"
  }

  assert {
    condition     = length(aws_ec2_tag.public_subnet_cluster) == 2
    error_message = "Expected cluster tag on 2 public subnets"
  }
}
