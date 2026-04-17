# Hello World — AWS Infrastructure

Infrastructure-as-code for a multi-environment, multi-region AWS deployment built on Terraform.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Directory Structure](#2-directory-structure)
3. [Environment Overview](#3-environment-overview)
4. [Architecture](#4-architecture)
5. [Getting Started](#5-getting-started)
6. [Day-to-Day Workflow](#6-day-to-day-workflow)
7. [Testing](#7-testing)
8. [Makefile Reference](#8-makefile-reference)

---

## 1. Prerequisites

Install the following tools before working with this repository.

| Tool | Min Version | Install (macOS) |
|------|-------------|-----------------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.10.0 | `brew install terraform` |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | 2.0 | `brew install awscli` |
| GNU Make | 3.81 | macOS: pre-installed |

### AWS authentication

```bash
# Option A — named profile
aws configure --profile hello-world
export AWS_PROFILE=hello-world

# Option B — environment variables
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-1
```

---

## 2. Directory Structure

```
.
├── Makefile
├── README.md
└── infra/
    ├── bootstrap/                    # One-time setup: S3 bucket + DynamoDB table
    │   ├── main.tf
    │   └── terraform.tfstate         # ⚠️  BACK THIS UP — store in 1Password / Vault
    │
    ├── modules/                      # Reusable, independently-testable modules
    │   ├── networking/               # VPC, subnets, IGW, NAT gateway, route tables
    │   ├── load-balancer/            # ALB, target group, listener, security group
    │   ├── compute/                  # EC2 Auto Scaling Group + IAM + launch template
    │   ├── lambda/                   # Lambda function + IAM + CloudWatch log group
    │   ├── rds/                      # RDS PostgreSQL + subnet group + Secrets Manager
    │   └── ecr/                      # ECR repository + lifecycle policy
    │       ├── versions.tf
    │       ├── variables.tf
    │       ├── main.tf
    │       └── outputs.tf
    │
    └── envs/                         # Per-environment root modules
        ├── dev/                      # Developer sandbox — single-region
        ├── test/                     # Internal QA — single-region
        ├── perf/                     # Performance testing — multi-region
        ├── staging/                  # Integration / UAT — multi-region
        └── production/               # Live workloads — multi-region
            ├── versions.tf           # Terraform + provider version constraints
            ├── backend.tf            # S3 remote state + DynamoDB lock + use_lockfile (dual-lock)
            ├── providers.tf          # AWS provider configuration + default_tags
            ├── variables.tf          # Input variable declarations (type + description)
            ├── main.tf               # Module calls
            ├── outputs.tf            # Output declarations
            └── terraform.tfvars      # Environment-specific variable values
```

---

## 3. Environment Overview

| Environment | Purpose | AWS Region(s) | NAT |
|-------------|---------|---------------|-----|
| **dev** | Developer sandbox — short-lived, low-cost | us-east-1 | ✗ |
| **test** | Internal QA testing | us-east-1 | ✗ |
| **perf** | Performance / load testing (mirrors prod sizing) | us-east-1 (primary) · us-west-2 (secondary) | ✓ |
| **staging** | Integration with internal/external teams · UAT | us-east-1 (primary) · us-west-2 (secondary) | ✓ |
| **production** | Live workloads | us-east-1 (primary) · us-west-2 (secondary) | ✓ |

### VPC CIDR allocation (non-overlapping for future peering)

| Environment | Region | VPC CIDR |
|-------------|--------|----------|
| dev | us-east-1 | 10.0.0.0/16 |
| test | us-east-1 | 10.1.0.0/16 |
| perf | us-east-1 | 10.2.0.0/16 |
| perf | us-west-2 | 10.3.0.0/16 |
| staging | us-east-1 | 10.4.0.0/16 |
| staging | us-west-2 | 10.5.0.0/16 |
| production | us-east-1 | 10.6.0.0/16 |
| production | us-west-2 | 10.7.0.0/16 |

---

## 4. Architecture

### State management

Terraform remote state is stored in **S3** with **DynamoDB locking**. The bootstrap configuration creates both resources once and stores its own state locally (`infra/bootstrap/terraform.tfstate`). Back this file up to a secure location (e.g. 1Password) — losing it means the bootstrap resources become unmanaged.

> **Note:** Backends use both `dynamodb_table` and `use_lockfile = true` (requires Terraform >= 1.10 + AWS provider >= 5.86). When both are configured, Terraform writes locks to DynamoDB **and** an S3 `.tflock` file, giving double protection during the migration period.

```
infra/envs/<env>/   →   S3: hello-world-terraform-state-*/
                              <env>/terraform.tfstate
                              <env>/terraform.tfstate.tflock  ← S3-native lock (use_lockfile)
                        DynamoDB: terraform-state-lock       ← legacy lock (dynamodb_table)
```

### Multi-region (perf / staging / production)

Each environment uses **provider aliases** to deploy identical infrastructure into two AWS regions simultaneously (**active-active**):

```
aws.primary   →  us-east-1  (active)
aws.secondary →  us-west-2  (active)
```

Both regions run independent VPCs, subnets, internet gateways, NAT gateways, and compute (ASG). The topology is intentionally symmetric so that either region can serve traffic independently:

- **Compute** — `compute_primary` and `compute_secondary` each run their own ASG behind a regional ALB. Traffic distribution (Route 53 latency/failover routing, Global Accelerator, etc.) is added as a separate module.
- **RDS** — single writer in `us-east-1` (primary) only. Secondary region reads from the application tier; Aurora Global Database or read replicas can be added as a separate concern.
- **ECR** — single registry in `us-east-1`; secondary region pulls images across regions. Cross-region replication can be enabled when pull latency is a concern.

| Environment | primary `desired_capacity` | secondary `desired_capacity` |
|-------------|---------------------------|------------------------------|
| perf        | 1                         | 1                            |
| staging     | 2                         | 2                            |
| production  | 2                         | 2                            |

### Module design

Modules follow these conventions:

- **Single responsibility** — one module per infrastructure concern
- **Provider-agnostic interface** — callers pass provider aliases; modules declare `required_providers` but do not configure credentials
- **Testable** — every module ships with a `tests/` directory using the built-in `terraform test` framework with `mock_provider` (no real credentials needed for unit tests)
- **Output-first** — all resource IDs and ARNs are exposed as outputs for use by dependent modules

---

## 5. Getting Started

### First-time setup

```bash
# 1. Configure AWS credentials (see Prerequisites above)

# 2. Bootstrap: create the S3 state bucket and DynamoDB lock table
make bootstrap-apply

# ⚠️  Back up infra/bootstrap/terraform.tfstate immediately after this step.

# 3. Initialise all five environments (downloads providers + configures S3 backend)
make init-all
```

---

## 6. Day-to-Day Workflow

```bash
# Plan changes for an environment
make plan ENV=dev

# Apply changes
make apply ENV=dev

# Apply to a protected environment (staging / production) — prompts for name confirmation
make apply ENV=staging
make apply ENV=production

# Destroy an environment (double confirmation required)
make destroy ENV=dev

# Validate HCL syntax for all environments
make validate-all

# Format all Terraform files in-place
make fmt

# Check formatting without writing (use in CI)
make fmt-check
```

---

## 7. Testing

Module tests use Terraform's built-in **`terraform test`** framework (≥ 1.7). Tests use `mock_provider "aws" {}` so they run without real AWS credentials — safe for local development and CI.

```bash
# Test a specific module
make test MODULE=networking

# Test all modules
make test-all
```

Test files live at `infra/modules/<name>/tests/*.tftest.hcl`. Each file:

- Covers the `plan` command only (no real resources created)
- Asserts on resource attributes (CIDR blocks, counts, flags)
- Includes scenarios: default config, optional features enabled, multi-AZ

### Adding tests for a new module

1. Create `infra/modules/<name>/tests/<name>_test.tftest.hcl`
2. Add `mock_provider` for each required provider
3. Write `run` blocks with `command = plan` and `assert` blocks
4. Run with `make test MODULE=<name>`

---

## 8. Makefile Reference

Run `make help` to see all targets with descriptions.

### Bootstrap

| Target | Description |
|--------|-------------|
| `make bootstrap-init` | `terraform init` for bootstrap (local backend) |
| `make bootstrap-plan` | `terraform plan` for bootstrap |
| `make bootstrap-apply` | Create S3 bucket + DynamoDB table — **run once** |
| `make bootstrap-output` | Print bootstrap outputs (bucket name, ARNs) |

### Single environment

| Target | Description |
|--------|-------------|
| `make init ENV=<name>` | `terraform init` |
| `make plan ENV=<name>` | `terraform plan` |
| `make apply ENV=<name>` | `terraform apply` (staging/production require typed confirmation) |
| `make destroy ENV=<name>` | `terraform destroy` (always requires typed confirmation) |
| `make validate ENV=<name>` | `terraform validate` |
| `make state-list ENV=<name>` | List resources in remote state |

### Bulk operations

| Target | Description |
|--------|-------------|
| `make init-all` | Init all 5 environments |
| `make validate-all` | Validate all 5 environments |
| `make plan-all` | Plan all 5 environments (read-only, safe for CI) |

### Module testing

| Target | Description |
|--------|-------------|
| `make test MODULE=<name>` | Run `terraform test` for a module |
| `make test-all` | Run `terraform test` for all modules with a `tests/` directory |

### Utilities

| Target | Description |
|--------|-------------|
| `make fmt` | Format all Terraform files in-place |
| `make fmt-check` | Check formatting without writing (CI) |
| `make lock-check` | List active DynamoDB state locks |
| `make lock-release` | Force-release a stuck lock (use with caution) |
