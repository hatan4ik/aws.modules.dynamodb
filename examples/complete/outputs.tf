output "table_name" {
  description = "Name of the table."
  value       = module.table.name
}

output "table_arn" {
  description = "ARN of the table."
  value       = module.table.arn
}

output "stream_arn" {
  description = "ARN of the DynamoDB stream."
  value       = module.table.stream_arn
}

output "stream_label" {
  description = "Timestamp label of the DynamoDB stream."
  value       = module.table.stream_label
}

output "global_secondary_index_arns" {
  description = "Global secondary index ARNs keyed by index name."
  value       = module.table.global_secondary_index_arns
}

output "local_secondary_index_arns" {
  description = "Local secondary index ARNs keyed by index name."
  value       = module.table.local_secondary_index_arns
}

output "resource_policy" {
  description = "Rendered resource-based policy document."
  value       = module.table.resource_policy
}
