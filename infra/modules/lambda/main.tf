locals {
  full_name = "${var.project}-${var.env}-${var.function_name}"

  # Minimal placeholder handler — replace via CI/CD pipeline deployment.
  placeholder_source = "def handler(event, context):\n    return {\"statusCode\": 200, \"body\": \"ok\"}\n"
}

# Placeholder zip — CI/CD overwrites this with a real deployment package.
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "/tmp/tf-lambda-${local.full_name}.zip"

  source {
    content  = local.placeholder_source
    filename = "index.py"
  }
}

# ─── IAM Role ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${local.full_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${local.full_name}-role"
  }
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ─── CloudWatch Log Group ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.full_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = local.full_name
  }
}

# ─── Lambda Function ──────────────────────────────────────────────────────────

resource "aws_lambda_function" "this" {
  function_name    = local.full_name
  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256
  role             = aws_iam_role.lambda.arn
  runtime          = var.runtime
  handler          = var.handler
  memory_size      = var.memory_size
  timeout          = var.timeout

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic,
    aws_cloudwatch_log_group.this,
  ]

  tags = {
    Name = local.full_name
  }
}

