# Pipeline Design

## Overview

All CI/CD runs on **GitHub Actions**. There are two independent pipeline tracks — **Infra** (Terraform) and **Service** (Python/Chalice) — orchestrated by a common PR Gate and Release workflow.

Workflow files: [`.github/workflows/`](../.github/workflows/)

---

## Workflow Inventory

| File | Trigger | Purpose |
|------|---------|---------|
| `pr-gate.yml` | PR → `main` | Detects scope, orders Infra CI before Service CI |
| `infra-ci.yml` | PR (infra paths) / `workflow_call` | fmt · validate · plan · OPA policy check |
| `infra-cd.yml` | `workflow_call` / `workflow_dispatch` | Sequential env promotion: dev → staging → production |
| `service-ci.yml` | `workflow_call` | secret-scan · lint · unit test · security scan · package · e2e |
| `service-cd.yml` | `workflow_call` | Build artifact → Terraform release gate → deploy Lambda → smoke test |
| `release.yml` | Push → `main` | Detects changes, chains: infra-ci → infra-cd → service-ci → service-cd |

---

## PR Gate (Pull Request → `main`)

```mermaid
flowchart TD
    PR([Pull Request opened / updated])
    PR --> DS[detect-scope\nDiff against base SHA]

    DS -->|infra/* changed| WIC[wait-infra-ci\nPoll until Infra CI completes]
    DS -->|service/* changed| SCI

    WIC -->|Infra CI ✅| SCI[call-service-ci\nService CI workflow]
    WIC -->|Infra CI ❌| FAIL([Pipeline fails])

    DS -->|service NOT changed| SKIP([Service CI skipped])

    SCI --> PASS([PR checks pass])
```

**Key rule**: if the same PR touches both infra and app code, Service CI is held until Infra CI passes. This prevents deploying application code against an infrastructure that may not yet be valid.

---

## Infra CI (on PR or called by Release)

```mermaid
flowchart TD
    START([Trigger: PR touching infra/**\nor workflow_call from release.yml])
    START --> SS1[Secret Scan\nGitleaks — full history]

    SS1 -->|parallel matrix: all 5 envs| FV["fmt-validate\nterraform fmt -check\nterraform init\nterraform validate"]
    FV --> PLAN["plan\nterraform plan → tfplan.binary\nterraform show -json → tfplan.json\nPost summary comment to PR"]
    PLAN --> OPA["opa-check\nconftest: terraform.secrets\nconftest: terraform.security_baseline"]

    OPA -->|all envs pass| DONE([Infra CI ✅])
    OPA -->|any env fails| FAIL([Infra CI ❌])

    style FV fill:#ddf,stroke:#99b
    style PLAN fill:#ddf,stroke:#99b
    style OPA fill:#ddf,stroke:#99b
```

- Each matrix stage runs **all 5 environments in parallel** (`fail-fast: false`)
- Stale runs on force-push are cancelled (`concurrency: cancel-in-progress: true`)
- Plan artifacts (`tfplan.binary`, `tfplan.json`) are uploaded and consumed by the OPA stage

---

## Infra CD (Sequential Environment Promotion)

Triggered by `release.yml` after Infra CI passes. Each job requires the previous to succeed — a failure stops the chain.

```mermaid
flowchart LR
    DEV["Apply / dev\n⚡ auto"]
    TEST["Apply / test\n⚡ auto"]
    PERF["Apply / perf\n⚡ auto"]
    STAGING["Apply / staging\n👤 reviewer approval\nrequired"]
    PROD["Apply / production\n👤 reviewer approval\nrequired"]

    DEV --> TEST --> PERF --> STAGING --> PROD
```

Each apply job:
1. Runs OPA `approval` policy check (pre-apply metadata)
2. `terraform init`
3. `terraform apply -var-file=terraform.tfvars -auto-approve`

> **Concurrency**: `cancel-in-progress: false` — a second push queues behind an in-flight apply instead of cancelling it (safer for infrastructure).

---

## Service CI

```mermaid
flowchart TD
    START([workflow_call from pr-gate or release])
    START --> SS[Secret Scan\nGitleaks]

    SS --> LINT[Lint\nflake8 · black · isort]
    SS --> UT[Unit Tests\npytest tests/unit/\ncoverage ≥ 70%]
    SS --> SEC[Security Scan\nBandit SAST\npip-audit CVE check\nTrivy Dockerfile scan]

    LINT & UT & SEC --> PKG[Chalice Package\nchalice package --stage dev\nVerify deployment.zip created]

    PKG --> E2E[E2E Smoke Test\ndocker compose + LocalStack\npytest tests/e2e/]

    E2E --> DONE([Service CI ✅])

    style LINT fill:#dfd,stroke:#6a6
    style UT fill:#dfd,stroke:#6a6
    style SEC fill:#dfd,stroke:#6a6
```

---

## Service CD

```mermaid
flowchart TD
    START([workflow_call from release.yml\nafter service-ci passes])

    START --> PKG[Test & Package\nchalice package → deployment.zip\nUpload artifact]

    PKG --> GATE[Terraform Release Gate\nRead enable_lambda from terraform.tfvars]

    GATE -->|enable_lambda = true| DEPLOY[Deploy — dev\nDownload artifact\nterraform apply -var deployment_package_path=...\naws lambda wait function-updated\nSmoke test GET /health]

    GATE -->|enable_lambda = false| SKIP[Skip Deploy\nLog: lambda disabled for env]

    GATE -->|enable_ecr = true| ECR[Build & Push — ECR\ndocker build + docker push\nTagged with git SHA + latest]

    DEPLOY --> DONE([Service CD ✅])
    SKIP --> DONE
    ECR --> DONE
```

> **Lambda deployment via Terraform** — the pipeline never calls `aws lambda update-function-code` directly. It passes the zip path as a Terraform variable; the `null_resource` in the lambda module calls the AWS CLI, keeping all resource management inside Terraform.

---

## Full Release Chain (Push → `main`)

```mermaid
flowchart TD
    PUSH([Push to main])
    PUSH --> DC[Detect Changed Paths\ngit diff HEAD~1 HEAD]

    DC -->|infra changed| ICI[Infra CI\nfmt · validate · plan · OPA]
    DC -->|infra NOT changed| SCI_WAIT

    ICI --> ICD[Infra CD\ndev → test → perf → staging ✋ → production ✋]

    ICD --> SCI_WAIT{App changed?}
    DC -->|app changed| SCI_WAIT

    SCI_WAIT -->|yes| SCI[Service CI\nlint · test · scan · package · e2e]
    SCI_WAIT -->|no| DONE_SKIP([Done — no app changes])

    SCI --> SCD[Service CD\npackage → release-gate → deploy-dev → smoke-test]
    SCD --> DONE([Release complete ✅])

    style ICD fill:#ffd,stroke:#aa8
    style SCD fill:#ffd,stroke:#aa8
```

**Concurrency**: the `release` concurrency group uses `cancel-in-progress: false` — only one release runs at a time, but a second push waits in queue rather than cancelling an in-flight deployment.

---

## Security Controls in Pipeline

| Control | Where |
|---------|-------|
| Gitleaks secret scan | First job in every CI workflow (blocks on secrets found) |
| Bandit SAST | Service CI — `security-scan` job |
| pip-audit CVE scan | Service CI — `security-scan` job |
| Trivy Dockerfile scan | Service CI — `security-scan` job |
| OPA / Conftest | Infra CI + Infra CD — policy checks on plan JSON and deployment metadata |
| OIDC (no static AWS keys) | All jobs that touch AWS use `configure-aws-credentials` with `role-to-assume` |
| GitHub Environment protection | `staging` and `production` require ≥ 1 reviewer before apply |
| Branch protection | All changes to `main` go through PR — enforced via GitHub branch rules |
