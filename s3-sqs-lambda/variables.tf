variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "bucket_name" {
  description = "S3 bucket name (must be globally unique)"
  type        = string
}

variable "queue_name" {
  description = "SQS queue name"
  type        = string
  default     = "s3-event-queue"
}

variable "lambda_function_name" {
  description = "Lambda function name"
  type        = string
  default     = "s3-object-logger"
}
