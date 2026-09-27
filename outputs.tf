output "id" {
  description = "Table ID (the table name)."
  value       = local.table.id
}

output "name" {
  description = "Table name."
  value       = local.table.name
}

output "arn" {
  description = "Table ARN."
  value       = local.table.arn
}

output "stream_arn" {
  description = "ARN of the DynamoDB stream, or null when stream is not declared."
  value       = var.stream == null ? null : local.table.stream_arn
}

output "stream_label" {
  description = "Timestamp label of the DynamoDB stream, or null when stream is not declared."
  value       = var.stream == null ? null : local.table.stream_label
}

output "hash_key" {
  description = "Partition key attribute name."
  value       = local.table.hash_key
}

output "range_key" {
  description = "Sort key attribute name, or null."
  value       = local.table.range_key
}

output "billing_mode" {
  description = "Billing mode of the table."
  value       = local.table.billing_mode
}

output "table_class" {
  description = "Storage class of the table."
  value       = local.table.table_class
}

output "global_secondary_index_arns" {
  description = "Global secondary index ARNs keyed by index name (<table arn>/index/<name>)."
  value       = { for name in keys(var.global_secondary_indexes) : name => "${local.table.arn}/index/${name}" }
}

output "local_secondary_index_arns" {
  description = "Local secondary index ARNs keyed by index name (<table arn>/index/<name>)."
  value       = { for name in keys(var.local_secondary_indexes) : name => "${local.table.arn}/index/${name}" }
}

output "replica_arns" {
  description = "Replica table ARNs keyed by region; empty when no replicas are declared."
  value       = { for replica in local.table.replica : replica.region_name => replica.arn }
}

output "autoscaling_target_resource_ids" {
  description = "Application Auto Scaling resource IDs keyed by dimension (table_read, table_write, index_<name>_read, index_<name>_write); empty when autoscaling is disabled."
  value       = length(module.autoscaling) == 0 ? {} : module.autoscaling[0].target_resource_ids
}

output "autoscaling_policy_arns" {
  description = "Target-tracking policy ARNs keyed by dimension; empty when autoscaling is disabled."
  value       = length(module.autoscaling) == 0 ? {} : module.autoscaling[0].policy_arns
}

output "resource_policy" {
  description = "Rendered resource-based policy JSON, or null when no statements are declared."
  value       = local.resource_policy
}
