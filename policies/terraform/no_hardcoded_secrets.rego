# policies/terraform/no_hardcoded_secrets.rego
#
# OPA policy — Task 3, Requirement 2:
# "A secret scanning step is in place to ensure no credentials are hardcoded."
#
# Input: Terraform plan JSON (terraform show -json tfplan.binary)
# Checks every resource_change.change.after attribute whose name suggests it
# holds a secret, and rejects any value that:
#   - matches known credential formats (AWS keys, private keys, tokens), OR
#   - is a non-empty string that is NOT a Terraform reference / ARN / path
#     (i.e. looks like a literal value rather than a managed secret reference)
#
# Usage:
#   conftest test tfplan.json \
#     --policy policies/terraform/ \
#     --namespace terraform.secrets

package terraform.secrets

import rego.v1

# ─── Attribute names that warrant scrutiny ───────────────────────────────────
sensitive_attr_names := {
	"password",
	"secret",
	"secret_string",
	"secret_key",
	"api_key",
	"api_secret",
	"access_key",
	"access_key_id",
	"secret_access_key",
	"private_key",
	"token",
	"auth_token",
	"oauth_token",
	"bearer_token",
	"credential",
	"credentials",
	"client_secret",
	"encryption_key",
	"signing_key",
	"webhook_secret",
}

# ─── Regex patterns that indicate a hardcoded credential ─────────────────────
# AWS access key ID
aws_access_key_pattern := `AKIA[0-9A-Z]{16}`

# AWS secret access key (40-char base64-like string after a keyword context)
aws_secret_key_pattern := `[A-Za-z0-9+/]{40}`

# Generic high-entropy secret patterns (base64, hex, JWT header)
jwt_pattern := `eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+`

private_key_header := `-----BEGIN`

# ─── Values that are safe (managed references, not literal secrets) ───────────
# A value is "safe" if it looks like a reference to a managed secret store or
# a Terraform-computed value rather than a literal credential.
is_safe_value(val) if {
	# AWS Secrets Manager ARN
	startswith(val, "arn:aws:secretsmanager:")
}

is_safe_value(val) if {
	# SSM Parameter Store path
	startswith(val, "/")
	contains(val, "/")
}

is_safe_value(val) if {
	# Terraform random_password output reference pattern in plan
	# (plan shows computed values as null or a sentinel)
	val == null
}

is_safe_value(val) if {
	# Empty string — intentional blank (e.g. optional password)
	val == ""
}

is_safe_value(val) if {
	# placeholder / dummy values used in tests
	lower(val) in {"placeholder", "changeme", "todo", "replace-me", "example"}
}

# ─── Rule: deny AWS access key IDs ───────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.change.actions[_] in {"create", "update"}
	key := object.keys(resource.change.after)[_]
	val := resource.change.after[key]
	is_string(val)
	regex.match(aws_access_key_pattern, val)
	msg := sprintf(
		"[%v] attribute '%v' contains what looks like an AWS Access Key ID. Use IAM roles or Secrets Manager instead.",
		[resource.address, key],
	)
}

# ─── Rule: deny PEM private key headers ──────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.change.actions[_] in {"create", "update"}
	key := object.keys(resource.change.after)[_]
	val := resource.change.after[key]
	is_string(val)
	contains(val, private_key_header)
	msg := sprintf(
		"[%v] attribute '%v' contains a PEM private key header. Store private keys in AWS Secrets Manager or SSM SecureString.",
		[resource.address, key],
	)
}

# ─── Rule: deny JWT tokens ────────────────────────────────────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.change.actions[_] in {"create", "update"}
	key := object.keys(resource.change.after)[_]
	val := resource.change.after[key]
	is_string(val)
	regex.match(jwt_pattern, val)
	msg := sprintf(
		"[%v] attribute '%v' contains what looks like a JWT token. Do not hardcode tokens in Terraform.",
		[resource.address, key],
	)
}

# ─── Rule: deny non-safe literal values in sensitive-named attributes ─────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.change.actions[_] in {"create", "update"}
	key := object.keys(resource.change.after)[_]

	# Only flag attributes whose name matches the sensitive list
	sensitive_key(key)

	val := resource.change.after[key]
	is_string(val)

	# Only flag non-empty values that don't look like managed references
	not is_safe_value(val)
	count(val) > 0

	msg := sprintf(
		"[%v] attribute '%v' appears to contain a literal secret value (length %v). Use aws_secretsmanager_secret or random_password instead.",
		[resource.address, key, count(val)],
	)
}

# ─── Rule: RDS password must come from random_password (not a literal) ───────
# In the plan JSON, random_password.result is "(sensitive value)" — if we see
# a non-sensitive, non-null password on an RDS instance, it is hardcoded.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type in {"aws_db_instance", "aws_rds_cluster"}
	resource.change.actions[_] in {"create", "update"}
	val := resource.change.after.password
	is_string(val)
	not is_safe_value(val)
	count(val) > 0
	msg := sprintf(
		"[%v] RDS password appears to be hardcoded. Use random_password + aws_secretsmanager_secret_version.",
		[resource.address],
	)
}

# ─── Helper: case-insensitive attribute name matching ────────────────────────
sensitive_key(key) if {
	lower(key) in sensitive_attr_names
}
