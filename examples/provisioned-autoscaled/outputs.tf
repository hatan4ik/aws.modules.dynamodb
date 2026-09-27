output "table_name" {
  description = "Name of the table."
  value       = module.table.name
}

output "table_arn" {
  description = "ARN of the table."
  value       = module.table.arn
}

output "autoscaling_target_resource_ids" {
  description = "Application Auto Scaling resource IDs keyed by dimension."
  value       = module.table.autoscaling_target_resource_ids
}

output "autoscaling_policy_arns" {
  description = "Target-tracking policy ARNs keyed by dimension."
  value       = module.table.autoscaling_policy_arns
}
