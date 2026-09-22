output "arn" {
  description = "ARN of the DynamoDB table."
  value       = aws_dynamodb_table.this.arn
}

output "id" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.this.id
}

output "stream_arn" {
  description = "DynamoDB stream ARN when streams are enabled by a future module version."
  value       = aws_dynamodb_table.this.stream_arn
}
