output "table_arns" {
  description = "Table ARNs keyed by table key."
  value       = { for key, table in module.table : key => table.arn }
}

output "table_names" {
  description = "Table names keyed by table key."
  value       = { for key, table in module.table : key => table.name }
}

output "stream_arns" {
  description = "Stream ARNs keyed by table key; null for tables without a stream."
  value       = { for key, table in module.table : key => table.stream_arn }
}
