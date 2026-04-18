data "aws_region" "current" {}

locals {
  prefix      = "${var.project}-${var.env}"
  api_fn_name = local.prefix
  sqs_fn_name = "${local.prefix}-${var.sqs_handler_suffix}"

  # When a real deployment package is provided (by service-cd), use it.
  # Otherwise fall back to the placeholder so infra-only runs stay valid.
  has_real_pkg = var.deployment_package_path != ""
  pkg_path     = local.has_real_pkg ? var.deployment_package_path : data.archive_file.placeholder.output_path
  pkg_hash     = filemd5(local.pkg_path)
}

# Placeholder zip — used on first apply and on infra-only runs.
# CI/CD deploys real code via the null_resource below.
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "/tmp/tf-lambda-${local.prefix}-placeholder.zip"

  source {
    content  = "def handler(event, context):\n    return {\"statusCode\": 200, \"body\": \"ok\"}\n"
    filename = "app.py"
  }
}

# ─── IAM Role ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${local.prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${local.prefix}-lambda-role"
  }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dynamodb" {
  name = "${local.prefix}-dynamodb"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:UpdateItem",
      ]
      Resource = var.dynamodb_table_arn
    }]
  })
}

resource "aws_iam_role_policy" "sqs_consumer" {
  name = "${local.prefix}-sqs-consumer"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
      ]
      Resource = var.sqs_queue_arn
    }]
  })
}

# ─── CloudWatch Log Groups ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "api_handler" {
  name              = "/aws/lambda/${local.api_fn_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = local.api_fn_name
  }
}

resource "aws_cloudwatch_log_group" "sqs_handler" {
  name              = "/aws/lambda/${local.sqs_fn_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = local.sqs_fn_name
  }
}

# ─── Lambda Functions ──────────────────────────────────────────────────────────
#
# Both functions are initialised with a placeholder handler.
# Real application code is deployed by the null_resource below whenever
# deployment_package_path is set (i.e. on every service-cd run).
# ignore_changes prevents infra-cd from reverting deployed code back to
# the placeholder when only infrastructure changes are applied.

resource "aws_lambda_function" "api_handler" {
  function_name    = local.api_fn_name
  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256
  role             = aws_iam_role.lambda.arn
  runtime          = var.runtime
  handler          = var.api_handler
  memory_size      = var.memory_size
  timeout          = var.timeout

  environment {
    variables = var.environment_variables
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic,
    aws_iam_role_policy.dynamodb,
    aws_cloudwatch_log_group.api_handler,
  ]

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = {
    Name = local.api_fn_name
  }
}

resource "aws_lambda_function" "sqs_handler" {
  function_name    = local.sqs_fn_name
  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256
  role             = aws_iam_role.lambda.arn
  runtime          = var.runtime
  handler          = var.sqs_handler
  memory_size      = var.memory_size
  timeout          = var.timeout

  environment {
    variables = var.environment_variables
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic,
    aws_iam_role_policy.dynamodb,
    aws_iam_role_policy.sqs_consumer,
    aws_cloudwatch_log_group.sqs_handler,
  ]

  lifecycle {
    ignore_changes = [filename, source_code_hash]
  }

  tags = {
    Name = local.sqs_fn_name
  }
}

# ─── Lambda Code Deployment ────────────────────────────────────────────────────
#
# Triggered whenever the deployment package content changes (content-addressed
# via MD5). Runs "aws lambda update-function-code" so that Terraform is the
# only tool the pipeline needs to invoke.
#
# When deployment_package_path is empty (infra-only runs), the provisioner
# prints a skip message and leaves existing Lambda code untouched.

resource "null_resource" "deploy_api_handler" {
  triggers = {
    package_hash  = local.pkg_hash
    function_name = aws_lambda_function.api_handler.function_name
  }

  provisioner "local-exec" {
    command = local.has_real_pkg ? "aws lambda update-function-code --function-name ${aws_lambda_function.api_handler.function_name} --zip-file fileb://${var.deployment_package_path} --region ${data.aws_region.current.name}" : "echo 'Skipping code deploy: no deployment_package_path provided'"
  }

  depends_on = [aws_lambda_function.api_handler]
}

resource "null_resource" "deploy_sqs_handler" {
  triggers = {
    package_hash  = local.pkg_hash
    function_name = aws_lambda_function.sqs_handler.function_name
  }

  provisioner "local-exec" {
    command = local.has_real_pkg ? "aws lambda update-function-code --function-name ${aws_lambda_function.sqs_handler.function_name} --zip-file fileb://${var.deployment_package_path} --region ${data.aws_region.current.name}" : "echo 'Skipping code deploy: no deployment_package_path provided'"
  }

  depends_on = [aws_lambda_function.sqs_handler]
}

# ─── SQS Event Source Mapping ──────────────────────────────────────────────────

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.sqs_handler.arn
  batch_size       = var.sqs_batch_size
  enabled          = true
}

# ─── API Gateway REST API ──────────────────────────────────────────────────────
#
# Uses a catch-all proxy integration (ANY / and ANY /{proxy+}) so that Chalice
# handles all routing internally. This avoids duplicating Chalice's route
# definitions in Terraform.

resource "aws_api_gateway_rest_api" "this" {
  name = local.prefix

  tags = {
    Name = local.prefix
  }
}

# Proxy resource: /{proxy+}
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

# Root: ANY /
resource "aws_api_gateway_method" "root" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_rest_api.this.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_rest_api.this.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

# Proxy: ANY /{proxy+}
resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  depends_on = [
    aws_api_gateway_integration.root,
    aws_api_gateway_integration.proxy,
  ]

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_integration.root,
      aws_api_gateway_integration.proxy,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.api_gateway_stage

  tags = {
    Name = local.prefix
  }
}

# Lambda permission for API Gateway to invoke the API handler
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

