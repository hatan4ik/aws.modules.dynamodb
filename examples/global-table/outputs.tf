output "table_arn" {
  description = "ARN of the primary table."
  value       = module.table.arn
}

output "replica_arns" {
  description = "Replica table ARNs keyed by region."
  value       = module.table.replica_arns
}

output "stream_arn" {
  description = "ARN of the primary table's stream."
  value       = module.table.stream_arn
}
