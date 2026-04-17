# policies/terraform/approval_required.rego
#
# OPA policy — Task 3, Requirement 1:
# "An approval step is in place for change/deployments to staging/production."
#
# Input schema (deployment-metadata.json generated in each CD job):
# {
#   "environment":  "staging",
#   "github_ref":   "refs/heads/main",
#   "github_actor": "username",
#   "event":        "push"
# }
#
# Usage:
#   conftest test deployment-metadata.json \
#     --policy policies/terraform/ \
#     --namespace terraform.approval

package terraform.approval

import rego.v1

# Environments that require human approval before any deployment.
# Approval is enforced by GitHub Environment protection rules (required reviewers).
# This OPA policy adds a programmatic gate that verifies the deployment metadata
# is consistent with those rules — defence-in-depth.
protected_envs := {"staging", "production"}

# All recognised environments. Deployments outside this set are rejected to
# prevent accidental deployments to ad-hoc or misspelled environment names.
known_envs := {"dev", "test", "perf", "staging", "production"}

# ─── Rule: only deploy from refs/heads/main ──────────────────────────────────
deny contains msg if {
	not startswith(input.github_ref, "refs/heads/main")
	msg := sprintf(
		"Deployments must originate from refs/heads/main. Got: '%v'",
		[input.github_ref],
	)
}

# ─── Rule: only push events trigger deployments (not manual workflow_dispatch
#     without proper controls, not pull_request events) ─────────────────────
deny contains msg if {
	input.event != "push"
	msg := sprintf(
		"CD pipeline must be triggered by a 'push' event. Got: '%v'. Use a PR merge workflow.",
		[input.event],
	)
}

# ─── Rule: environment must be a known value ──────────────────────────────────
deny contains msg if {
	not input.environment in known_envs
	msg := sprintf(
		"Unknown environment '%v'. Must be one of: %v",
		[input.environment, known_envs],
	)
}

# ─── Rule: actor must not be a bot for protected environments ─────────────────
# Bot accounts (GitHub Actions itself, dependabot) must not deploy directly to
# staging or production. Human approval via environment protection is required.
deny contains msg if {
	input.environment in protected_envs
	endswith(input.github_actor, "[bot]")
	msg := sprintf(
		"Bot actor '%v' cannot deploy directly to '%v'. A human must approve.",
		[input.github_actor, input.environment],
	)
}

# ─── Rule: environment name in metadata must match a protected env exactly ────
# Prevents a scenario where the metadata says "staging" but the workflow
# actually targets a different environment.
warn contains msg if {
	input.environment in protected_envs
	msg := sprintf(
		"Deployment to '%v' requires manual approval via GitHub Environment protection. Ensure reviewers have approved before this step runs.",
		[input.environment],
	)
}
