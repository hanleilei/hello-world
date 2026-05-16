# ─── EKS Cluster IAM Role ─────────────────────────────────────────────────────

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.project}-${var.env}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = {
    Name = "${var.project}-${var.env}-eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── Cluster Security Group ───────────────────────────────────────────────────

resource "aws_security_group" "cluster" {
  name_prefix = "${var.project}-${var.env}-eks-cluster-"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "${var.project}-${var.env}-eks-cluster-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─── EKS Cluster ──────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = "${var.project}-${var.env}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = {
    Name = "${var.project}-${var.env}-eks"
  }
}

# ─── OIDC Provider (for IRSA) ─────────────────────────────────────────────────

data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.project}-${var.env}-eks-oidc"
  }
}

# ─── Node Group IAM Role ──────────────────────────────────────────────────────

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node_group" {
  name               = "${var.project}-${var.env}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = {
    Name = "${var.project}-${var.env}-eks-node-role"
  }
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ─── Cilium ENI permissions ───────────────────────────────────────────────────
# Cilium runs in CNI chaining mode alongside the AWS VPC CNI. These additional
# EC2 permissions allow Cilium to read network topology for policy enforcement
# and BPF-based load balancing.

data "aws_iam_policy_document" "cilium_eni" {
  statement {
    sid    = "CiliumENIAccess"
    effect = "Allow"
    actions = [
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:CreateTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cilium_eni" {
  name        = "${var.project}-${var.env}-cilium-eni"
  description = "Allows Cilium to read EC2 network topology for policy and load balancing."
  policy      = data.aws_iam_policy_document.cilium_eni.json

  tags = {
    Name = "${var.project}-${var.env}-cilium-eni"
  }
}

resource "aws_iam_role_policy_attachment" "node_cilium_eni" {
  role       = aws_iam_role.node_group.name
  policy_arn = aws_iam_policy.cilium_eni.arn
}

# ─── Managed Node Group ───────────────────────────────────────────────────────

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project}-${var.env}-nodes"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.node_instance_types
  disk_size       = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_readonly,
    aws_iam_role_policy_attachment.node_cilium_eni,
  ]

  tags = {
    Name = "${var.project}-${var.env}-node-group"
  }
}

# ─── Kubernetes subnet tags for EKS load balancers ───────────────────────────

resource "aws_ec2_tag" "private_subnet_cluster" {
  count       = length(var.private_subnet_ids)
  resource_id = var.private_subnet_ids[count.index]
  key         = "kubernetes.io/cluster/${aws_eks_cluster.this.name}"
  value       = "shared"
}

resource "aws_ec2_tag" "private_subnet_internal_elb" {
  count       = length(var.private_subnet_ids)
  resource_id = var.private_subnet_ids[count.index]
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_subnet_cluster" {
  count       = length(var.public_subnet_ids)
  resource_id = var.public_subnet_ids[count.index]
  key         = "kubernetes.io/cluster/${aws_eks_cluster.this.name}"
  value       = "shared"
}

resource "aws_ec2_tag" "public_subnet_elb" {
  count       = length(var.public_subnet_ids)
  resource_id = var.public_subnet_ids[count.index]
  key         = "kubernetes.io/role/elb"
  value       = "1"
}
