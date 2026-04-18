variable "project" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.12"
}

variable "api_handler" {
  description = "Handler for the API Lambda function (file.function notation)"
  type        = string
  default     = "handler.api_handler"
}

variable "sqs_handler" {
  description = "Handler for the SQS Lambda function (file.function notation)"
  type        = string
  default     = "app.handle_processor_queue"
}

variable "sqs_handler_suffix" {
  description = "Name suffix appended to <project>-<env> for the SQS handler function"
  type        = string
  default     = "processor"
}

variable "memory_size" {
  description = "Memory allocated to each function in MB"
  type        = number
  default     = 128
}

variable "timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 30
}

variable "environment_variables" {
  description = "Environment variables injected into both Lambda functions"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}

variable "deployment_package_path" {
  description = "Local path to the Chalice deployment ZIP. Leave empty to keep existing code (infra-only runs)."
  type        = string
  default     = ""
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table the Lambda functions read/write"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue that triggers the SQS handler function"
  type        = string
}

variable "sqs_batch_size" {
  description = "Number of SQS messages processed per Lambda invocation"
  type        = number
  default     = 1
}

variable "api_gateway_stage" {
  description = "API Gateway deployment stage name"
  type        = string
  default     = "api"
}

