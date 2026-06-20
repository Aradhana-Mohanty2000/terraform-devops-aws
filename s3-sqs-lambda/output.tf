output "bucket_name" {
  value = aws_s3_bucket.this.id
}

output "queue_url" {
  value = aws_sqs_queue.this.id
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}
