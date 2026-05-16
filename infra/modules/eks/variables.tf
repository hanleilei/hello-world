# ─── Core ─────────────────────────────────────────────────────────────────────

variable "project" {
  description = "Project name used as a prefix for all resource names."
  type        = string
}

variable "env" {
  description = "Deployment environment name."
  type        = string
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vpc_id" {
  description = "ID of the VPC to deploy the EKS cluster into."
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for EKS node groups."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs to tag for external load balancers."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs to tag for internal load balancers."
  type        = list(string)
}

# ─── Cluster ──────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.35"
}

variable "endpoint_public_access" {
  description = "Enable public access to the EKS API server endpoint."
  type        = bool
  default     = true
}

# ─── Node Group ───────────────────────────────────────────────────────────────

variable "node_instance_types" {
  description = "List of EC2 instance types for managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Root EBS volume size (GiB) for worker nodes."
  type        = number
  default     = 20
}
