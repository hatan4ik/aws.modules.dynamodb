output "target_resource_ids" {
  description = "Application Auto Scaling resource IDs keyed by dimension (table_read, table_write, index_<name>_read, index_<name>_write)."
  value       = { for key, target in aws_appautoscaling_target.this : key => target.resource_id }

  precondition {
    condition     = length(local.dimensions) > 0
    error_message = "Nothing to scale: declare at least one of table.read, table.write, or an indexes entry."
  }
}

output "target_arns" {
  description = "Scalable target ARNs keyed by dimension."
  value       = { for key, target in aws_appautoscaling_target.this : key => target.arn }
}

output "policy_arns" {
  description = "Target-tracking policy ARNs keyed by dimension."
  value       = { for key, policy in aws_appautoscaling_policy.this : key => policy.arn }
}
