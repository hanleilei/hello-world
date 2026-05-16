# Test Report

**Project:** Hello World — AWS Multi-Environment Serverless API  
**Repository:** https://github.com/hanleilei/hello-world  
**Report Date:** 2026-04-20  
**Executed By:** Local machine (macOS) + GitHub Actions CI/CD  
**Deployed Endpoint:** https://bb0to0c3wf.execute-api.us-east-1.amazonaws.com/api

---

## Summary

| Test Suite | Total | Passed | Failed | Pass Rate |
|------------|------:|-------:|-------:|----------:|
| Unit Tests | 15 | 15 | 0 | **100%** |
| E2E Tests (Live Lambda) | 5 | 3 | 2 | **60%** |
| Terraform Module Tests | 3 | 3 | 0 | **100%** |
| **Total** | **23** | **21** | **2** | **91%** |

---

## 1. Unit Tests

**Runner:** pytest 8.4.2 / Python 3.13.9 (macOS)  
**Strategy:** moto mocks all AWS SDK calls in-process; `chalice.test.Client` invokes handlers directly — no network, no real AWS credentials required.  
**Command:**
```bash
pytest tests/unit/ -v --tb=short --cov=src --cov-report=term-missing
```

### Results

| Test | Module | Status |
|------|--------|--------|
| `test_health` | test_health.py | ✅ PASSED |
| `test_root` | test_health.py | ✅ PASSED |
| `test_create_item` | test_items.py | ✅ PASSED |
| `test_list_items_empty` | test_items.py | ✅ PASSED |
| `test_list_items` | test_items.py | ✅ PASSED |
| `test_read_item` | test_items.py | ✅ PASSED |
| `test_read_item_not_found` | test_items.py | ✅ PASSED |
| `test_delete_item` | test_items.py | ✅ PASSED |
| `test_delete_item_not_found` | test_items.py | ✅ PASSED |
| `test_create_item_missing_name` | test_items.py | ✅ PASSED |
| `test_sqs_create_item` | test_sqs.py | ✅ PASSED |
| `test_sqs_with_description` | test_sqs.py | ✅ PASSED |
| `test_sqs_unknown_action_is_skipped` | test_sqs.py | ✅ PASSED |
| `test_sqs_multiple_records` | test_sqs.py | ✅ PASSED |
| `test_sqs_malformed_body_does_not_crash` | test_sqs.py | ✅ PASSED |

**Result: 15 passed, 0 failed — duration 1.35s**

### Code Coverage

| File | Statements | Missed | Coverage |
|------|-----------|--------|----------|
| `src/app.py` | 57 | 1 | **98%** |
| `src/chalicelib/__init__.py` | 0 | 0 | **100%** |
| `src/chalicelib/db.py` | 43 | 9 | **79%** |
| **Total** | **100** | **10** | **90%** |

> Coverage threshold configured at 70% (`--cov-fail-under=70`). **Threshold met.**  
> The 9 uncovered lines in `db.py` are the `ensure_table_if_local()` function, which is only exercised when `AWS_ENDPOINT_URL` is set (LocalStack path) — covered by e2e tests instead.

---

## 2. E2E Tests — Live Lambda (API Gateway)

**Target:** `https://bb0to0c3wf.execute-api.us-east-1.amazonaws.com/api`  
**Strategy:** `httpx` sends real HTTP requests to the deployed Lambda via API Gateway. DynamoDB is the live AWS table `hello-world-items-dev`.  
**Command:**
```bash
APP_BASE_URL="https://bb0to0c3wf.execute-api.us-east-1.amazonaws.com/api" \
  pytest tests/e2e/ -v --tb=short
```

### Results

| Test | Endpoint(s) Exercised | Status | Note |
|------|----------------------|--------|------|
| `test_health` | `GET /health` | ✅ PASSED | Returns `{"status": "ok", "uptime_seconds": ...}` |
| `test_root` | `GET /` | ✅ PASSED | Returns `{"message": "hello-world", ...}` |
| `test_create_item_missing_name` | `POST /items` (empty body) | ✅ PASSED | Returns `400 Bad Request` as expected |
| `test_item_lifecycle` | `POST /items`, `GET /items/{id}`, `GET /items`, `DELETE /items/{id}` | ❌ FAILED | `GET /items/{id}` returns `405` |
| `test_item_not_found` | `GET /items/does-not-exist` | ❌ FAILED | Returns `405` instead of `404` |

**Result: 3 passed, 2 failed — duration 9.04s**

### Failure Analysis

Both failures return HTTP `405 Method Not Allowed` on paths with dynamic segments (`/items/{item_id}`). Static paths (`/health`, `/`, `/items`) work correctly.

**Root Cause:** API Gateway requires a new deployment to be created after resource changes. The `/{proxy+}` catch-all resource is defined in Terraform but the stage has not been redeployed since the last infrastructure change, causing API Gateway to return `405` for parameterised paths instead of forwarding to Lambda.

**Fix:** Trigger `Infra CD` workflow via `workflow_dispatch` in GitHub Actions to run `terraform apply`, which recreates the API Gateway deployment. No code changes required.

---

## 3. Terraform Module Tests

**Framework:** Terraform built-in `terraform test` (≥ 1.7)  
**Strategy:** `mock_provider "aws" {}` — no real AWS credentials required; runs `plan` only, no real resources created.  
**Command:**
```bash
cd infra/modules/networking && terraform init -backend=false && terraform test
```

### Results

| Test Run | Scenario | Status |
|----------|---------|--------|
| `vpc_without_nat` | Basic VPC, 2 AZs, NAT disabled | ✅ PASSED |
| `vpc_with_nat` | VPC with NAT Gateway enabled | ✅ PASSED |
| `multi_az_subnets` | Multi-AZ subnet spread validation | ✅ PASSED |

**Result: 3 passed, 0 failed**

**Modules with tests:** `networking`  
**Modules pending tests:** `compute`, `lambda`, `load-balancer`, `rds`, `ecr`

---

## 4. CI/CD Pipeline Tests

Tests are also executed automatically in GitHub Actions on every PR and push to `main`.

### Pipeline Stages (Service CI)

| Stage | Tool | Gates |
|-------|------|-------|
| Secret Scan | Gitleaks | Blocks on any detected secrets |
| Lint | flake8 · black · isort | PEP8 + consistent formatting |
| Unit Tests | pytest + moto | Coverage ≥ 70%, all tests pass |
| Security Scan | Bandit · pip-audit · Trivy | No HIGH/CRITICAL issues |
| Chalice Package | `chalice package` | Deployment zip must build successfully |
| E2E Smoke Test | docker-compose + LocalStack | Full lifecycle against emulated AWS |

### Pipeline Stages (Infra CI)

| Stage | Tool | Gates |
|-------|------|-------|
| Secret Scan | Gitleaks | Blocks on any detected secrets |
| Format Check | `terraform fmt -check` | All 5 environments |
| Validate | `terraform validate` | All 5 environments |
| Plan | `terraform plan` | All 5 environments; output posted to PR |
| OPA Policy Check | Conftest | `terraform.secrets` + `terraform.security_baseline` namespaces |

> For pipeline execution screenshots, see GitHub Actions: https://github.com/hanleilei/hello-world/actions

---

## 5. Known Issues

| # | Severity | Component | Description | Status |
|---|----------|-----------|-------------|--------|
| 1 | Medium | API Gateway (dev) | `GET/DELETE /items/{id}` returns `405` — stage needs redeployment | Pending `infra-cd` re-run via `workflow_dispatch` |

---

## 6. Test Environment

| Item | Value |
|------|-------|
| OS (local) | macOS |
| Python | 3.13.9 |
| pytest | 8.4.2 |
| Terraform | 1.10.0 |
| AWS Provider | 5.100.0 |
| Deployed Region | us-east-1 |
| Lambda Runtime | Python 3.12 |
| DynamoDB Table | `hello-world-items-dev` |
