output "table_name" {
  description = "Name of the table."
  value       = module.table.name
}

output "table_arn" {
  description = "ARN of the table."
  value       = module.table.arn
}

output "table_id" {
  description = "ID of the table."
  value       = module.table.id
}
