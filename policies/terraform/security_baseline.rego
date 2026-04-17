# policies/terraform/security_baseline.rego
#
# OPA policy — Infrastructure security baseline checks.
#
# Rule 1: No :latest image tag
#   Container images referenced in Terraform must use an explicit, immutable tag.
#   Using :latest prevents reproducible deployments and bypasses rollback safety.
#   Applies to: aws_lambda_function (container), aws_ecs_task_definition,
#               aws_instance / aws_launch_template user_data inline images,
#               and any resource attribute named "image" or "image_uri".
#
# Rule 2: Service-linked role guard
#   aws_iam_service_linked_role resources must not be created via Terraform
#   unless the service_name is in the approved list.
#   Rationale: service-linked roles are created automatically by AWS on first
#   use of the service. Manually creating them in Terraform can cause drift and
#   "already exists" errors in CI. When they must be pre-created (e.g. ELB),
#   only approved service names are permitted.
#
# Rule 3: VPC must enable DNS support and DNS hostnames
#   Required for AWS PrivateLink, VPC endpoints, and ECS service discovery to
#   function correctly. Disabling either silently breaks service-to-service
#   connectivity.
#
# Usage:
#   conftest test tfplan.json \
#     --policy policies/terraform/ \
#     --namespace terraform.security_baseline

package terraform.security_baseline

import rego.v1

# ─── Approved service-linked role service names ───────────────────────────────
# Only these AWS service principals may be created as service-linked roles via
# Terraform. Add entries here after a team review.
approved_service_linked_roles := {
	"elasticloadbalancing.amazonaws.com",
	"autoscaling.amazonaws.com",
}

# ─── Rule 1a: aws_lambda_function — container image must not use :latest ──────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_lambda_function"
	resource.change.actions[_] in {"create", "update"}
	uri := resource.change.after.image_uri
	is_string(uri)
	endswith(uri, ":latest")
	msg := sprintf(
		"[%v] aws_lambda_function.image_uri must not use the ':latest' tag. Pin to an explicit image digest or semantic version tag.",
		[resource.address],
	)
}

# ─── Rule 1b: aws_ecs_task_definition — all container images must not use :latest
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_ecs_task_definition"
	resource.change.actions[_] in {"create", "update"}

	# container_definitions is a JSON-encoded string in the plan
	defs_raw := resource.change.after.container_definitions
	is_string(defs_raw)
	defs := json.unmarshal(defs_raw)

	container := defs[_]
	image := container.image
	is_string(image)

	# Flag both bare "name:latest" and "registry/name:latest"
	endswith(image, ":latest")

	msg := sprintf(
		"[%v] ECS container '%v' uses image '%v' which ends in ':latest'. Use an explicit tag or digest.",
		[resource.address, container.name, image],
	)
}

# ─── Rule 1c: aws_launch_template — user_data must not reference :latest ──────
# user_data is base64-encoded; check the decoded value for image pull commands.
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_launch_template"
	resource.change.actions[_] in {"create", "update"}
	user_data := resource.change.after.user_data
	is_string(user_data)
	decoded := base64.decode(user_data)
	contains(decoded, ":latest")
	msg := sprintf(
		"[%v] aws_launch_template.user_data references a ':latest' image tag. Pin images to explicit tags in the launch template startup script.",
		[resource.address],
	)
}

# ─── Rule 1d: generic image / image_uri attributes on any resource ────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.change.actions[_] in {"create", "update"}
	key in {"image", "image_uri", "image_url", "container_image"}
	val := resource.change.after[key]
	is_string(val)
	endswith(val, ":latest")
	msg := sprintf(
		"[%v] attribute '%v' must not use the ':latest' tag. Value: '%v'",
		[resource.address, key, val],
	)
}

# ─── Rule 2: aws_iam_service_linked_role — only approved services ──────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_iam_service_linked_role"
	resource.change.actions[_] in {"create", "update"}
	svc := resource.change.after.aws_service_name
	not svc in approved_service_linked_roles
	msg := sprintf(
		"[%v] Creating a service-linked role for '%v' via Terraform is not approved. AWS auto-creates service-linked roles on first service use. Add to 'approved_service_linked_roles' in security_baseline.rego only after team review.",
		[resource.address, svc],
	)
}

# ─── Rule 3a: aws_vpc — enable_dns_support must be true ──────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_vpc"
	resource.change.actions[_] in {"create", "update"}
	resource.change.after.enable_dns_support == false
	msg := sprintf(
		"[%v] aws_vpc must have enable_dns_support = true. Disabling DNS support breaks VPC endpoints, PrivateLink, and ECS service discovery.",
		[resource.address],
	)
}

# ─── Rule 3b: aws_vpc — enable_dns_hostnames must be true ────────────────────
deny contains msg if {
	resource := input.resource_changes[_]
	resource.type == "aws_vpc"
	resource.change.actions[_] in {"create", "update"}
	resource.change.after.enable_dns_hostnames == false
	msg := sprintf(
		"[%v] aws_vpc must have enable_dns_hostnames = true. Disabling DNS hostnames prevents EC2 instances from receiving private DNS names, which breaks service discovery and PrivateLink.",
		[resource.address],
	)
}
