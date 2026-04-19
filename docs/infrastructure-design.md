# Infrastructure Design

## Overview

Infrastructure is managed entirely by **Terraform ≥ 1.10** and organized into reusable modules consumed by per-environment root modules. State is stored remotely in S3 with dual-lock protection.

Full environment details: [README.md §3](../README.md#3-environment-overview)

---

## Environment Matrix

| Environment | Purpose | Regions | NAT | Multi-region |
|-------------|---------|---------|-----|--------------|
| `dev` | Developer sandbox | us-east-1 | ✗ | ✗ |
| `test` | Internal QA | us-east-1 | ✗ | ✗ |
| `perf` | Load / performance testing | us-east-1 + us-west-2 | ✓ | ✓ |
| `staging` | Integration / UAT | us-east-1 + us-west-2 | ✓ | ✓ |
| `production` | Live workloads | us-east-1 + us-west-2 | ✓ | ✓ |

---

## State Management

```mermaid
flowchart LR
    subgraph Bootstrap ["infra/bootstrap/ (local state — back up manually)"]
        B_S3["S3 Bucket\nhello-world-terraform-state-*"]
        B_DDB["DynamoDB Table\nterraform-state-lock"]
    end

    subgraph "infra/envs/{env}/"
        TF["Terraform root module"]
        BE["backend.tf\nS3 + DynamoDB + use_lockfile"]
    end

    TF -->|"reads/writes state"| B_S3
    TF -->|"acquires lock"| B_DDB
    BE -.->|"dual-lock: S3 .tflock\n+ DynamoDB record"| B_S3 & B_DDB
```

> **Dual-lock**: backends set both `dynamodb_table` and `use_lockfile = true`, requiring Terraform ≥ 1.10 and AWS provider ≥ 5.86. This writes locks to DynamoDB **and** an S3 `.tflock` file simultaneously.

---

## Module Architecture

```mermaid
flowchart TB
    subgraph "infra/modules/"
        NET["networking\nVPC · Public/Private Subnets\nIGW · NAT Gateway\nRoute Tables"]
        LB["load-balancer\nALB · Target Group\nListener · Security Group"]
        COMP["compute\nEC2 Auto Scaling Group\nLaunch Template · IAM Role"]
        LAM["lambda\nAPI Lambda Function\nSQS Lambda Function\nAPI Gateway (/{proxy+})\nCloudWatch Log Groups · IAM"]
        RDS["rds\nRDS PostgreSQL\nSubnet Group\nSecrets Manager password"]
        ECR["ecr\nECR Repository\nLifecycle Policy"]
    end

    NET -->|"vpc_id, subnet_ids"| LB
    NET -->|"vpc_id, private_subnet_ids"| COMP
    NET -->|"vpc_id, private_subnet_ids"| RDS
    LB -->|"security_group_id, target_group_arn"| COMP
    COMP -->|"security_group_id"| RDS
```

Every module follows these conventions:

- **Single responsibility** — one module per infrastructure concern
- **Output-first** — all resource IDs/ARNs exposed as outputs
- **Provider-agnostic** — callers pass provider aliases; modules never configure credentials
- **Testable** — ships with `tests/<name>_test.tftest.hcl` using `mock_provider "aws" {}`

---

## Single-Region Architecture (dev / test)

```mermaid
flowchart TB
    subgraph "us-east-1"
        subgraph VPC ["VPC — 10.x.0.0/16"]
            subgraph Public ["Public Subnets"]
                ALB["ALB\n(enable_load_balancer)"]
                IGW["Internet Gateway"]
            end
            subgraph Private ["Private Subnets"]
                ASG["EC2 ASG\n(enable_compute)"]
                RDS_I["RDS PostgreSQL\n(enable_rds)"]
            end
            NAT["NAT Gateway\n(enable_nat_gateway)"]
        end

        LAM_F["API Lambda\n(enable_lambda)"]
        SQS_Q[("SQS Queue\nprocessor")]
        APIGW["API Gateway"]
        DDB[("DynamoDB\nhello-world-items-{env}")]
        ECR_R["ECR Repository\n(enable_ecr)"]
        CW["CloudWatch Logs"]
    end

    Internet((Internet))
    Internet --> IGW
    Internet -->|HTTPS| APIGW
    IGW --> ALB
    ALB --> ASG
    ASG -.->|egress| NAT
    NAT -.->|egress| Internet
    APIGW --> LAM_F
    SQS_Q --> LAM_F
    LAM_F --> DDB
    LAM_F --> CW
    ASG --> DDB
```

Feature flags in `terraform.tfvars` control which modules are active:

```hcl
enable_networking    = true
enable_load_balancer = false
enable_compute       = false
enable_lambda        = true   # Lambda + API Gateway
enable_rds           = false
enable_ecr           = false
```

---

## Multi-Region Architecture (perf / staging / production)

Provider aliases deploy identical infrastructure into two regions **simultaneously (active-active)**:

```mermaid
flowchart TB
    subgraph "us-east-1 (aws.primary)"
        subgraph VPC_P ["VPC — 10.x.0.0/16 (primary)"]
            ALB_P["ALB (primary)"]
            ASG_P["EC2 ASG (primary)\ndesired: 2"]
        end
        LAM_P["API Lambda (primary)"]
        DDB_P[("DynamoDB (primary)\nhello-world-items-{env}")]
        RDS_P[("RDS PostgreSQL\nprimary writer")]
        ECR_P["ECR (primary)\nus-east-1 only"]
    end

    subgraph "us-west-2 (aws.secondary)"
        subgraph VPC_S ["VPC — 10.x.0.0/16 (secondary)"]
            ALB_S["ALB (secondary)"]
            ASG_S["EC2 ASG (secondary)\ndesired: 2"]
        end
        LAM_S["API Lambda (secondary)"]
        DDB_S[("DynamoDB (secondary)\nhello-world-items-{env}")]
    end

    Traffic((Traffic)) -->|"latency routing\nor failover"| ALB_P & ALB_S
    ALB_P --> ASG_P
    ALB_S --> ASG_S
    ASG_P & ASG_S & LAM_P & LAM_S --> DDB_P
    ASG_S & LAM_S -.->|"cross-region reads\n(app tier)"| DDB_P
    ASG_P -->|"pulls images"| ECR_P
    ASG_S -->|"cross-region pull"| ECR_P
```

> **RDS** — single writer in `us-east-1` only. Aurora Global Database or read replicas can be added as a separate concern.  
> **ECR** — single registry in `us-east-1`; cross-region replication can be enabled when pull latency is a concern.

---

## Security Controls

| Layer | Control |
|-------|---------|
| **IAM** | OIDC federation — no long-lived AWS keys in CI/CD |
| **Secrets** | RDS credentials in Secrets Manager; no plaintext in Terraform state |
| **SQS** | SSE enabled (`sqs_managed_sse_enabled = true`) |
| **OPA / Conftest** | Policy-as-code checks on every `terraform plan` output: no hardcoded secrets, no `:latest` image tags, approved service-linked roles only, VPC DNS settings enforced |
| **Protected envs** | `staging` / `production` require typed name confirmation in CLI and a GitHub Environment reviewer approval in CI/CD |
| **State locking** | Dual-lock (DynamoDB + S3 `.tflock`) prevents concurrent applies |

---

## VPC CIDR Allocation

Pre-allocated, non-overlapping blocks reserved for future VPC peering:

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
