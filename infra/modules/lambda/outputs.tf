output "api_handler_arn" {
  description = "ARN of the API handler Lambda function"
  value       = aws_lambda_function.api_handler.arn
}

output "api_handler_name" {
  description = "Name of the API handler Lambda function"
  value       = aws_lambda_function.api_handler.function_name
}

output "sqs_handler_arn" {
  description = "ARN of the SQS handler Lambda function"
  value       = aws_lambda_function.sqs_handler.arn
}

output "sqs_handler_name" {
  description = "Name of the SQS handler Lambda function"
  value       = aws_lambda_function.sqs_handler.function_name
}

output "role_arn" {
  description = "ARN of the shared Lambda IAM role"
  value       = aws_iam_role.lambda.arn
}

output "api_endpoint_url" {
  description = "Base invoke URL of the API Gateway REST API"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.this.id
}
