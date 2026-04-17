# Uses Terraform's built-in test framework (requires terraform >= 1.7).
# Run with: terraform test   (from infra/modules/networking/)
#
# mock_provider avoids the need for real AWS credentials in CI.

mock_provider "aws" {}

# ─── Test 1: Basic VPC without NAT gateway ────────────────────────────────────

run "vpc_without_nat" {
  command = plan

  variables {
    project              = "hello-world"
    env                  = "test"
    vpc_cidr             = "10.0.0.0/16"
    public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
    private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
    azs                  = ["us-east-1a", "us-east-1b"]
    enable_nat_gateway   = false
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR should be 10.0.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true
    error_message = "DNS support should be enabled"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS hostnames should be enabled"
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Expected 2 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 2
    error_message = "Expected 2 private subnets"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "NAT gateway should not be created when enable_nat_gateway = false"
  }

  assert {
    condition     = length(aws_eip.nat) == 0
    error_message = "EIP should not be created when NAT gateway is disabled"
  }
}

# ─── Test 2: VPC with NAT gateway enabled ─────────────────────────────────────

run "vpc_with_nat" {
  command = plan

  variables {
    project              = "hello-world"
    env                  = "test"
    vpc_cidr             = "10.0.0.0/16"
    public_subnet_cidrs  = ["10.0.0.0/24"]
    private_subnet_cidrs = ["10.0.10.0/24"]
    azs                  = ["us-east-1a"]
    enable_nat_gateway   = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "Expected exactly 1 NAT gateway"
  }

  assert {
    condition     = length(aws_eip.nat) == 1
    error_message = "Expected exactly 1 EIP for NAT gateway"
  }

  assert {
    condition     = length(aws_route_table.private) == 1
    error_message = "Expected a private route table when NAT is enabled"
  }
}

# ─── Test 3: Multi-AZ deployment ──────────────────────────────────────────────

run "multi_az_subnets" {
  command = plan

  variables {
    project              = "hello-world"
    env                  = "perf"
    vpc_cidr             = "10.2.0.0/16"
    public_subnet_cidrs  = ["10.2.0.0/24", "10.2.1.0/24", "10.2.2.0/24"]
    private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]
    azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
    enable_nat_gateway   = true
  }

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Expected 3 public subnets for 3-AZ deployment"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Expected 3 private subnets for 3-AZ deployment"
  }
}
