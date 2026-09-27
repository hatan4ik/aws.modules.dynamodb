output "name" {
  description = "Unique table name for the suite."
  value       = local.name
}

output "account_id" {
  description = "Account the suite runs in, resolved from the caller's credentials."
  value       = data.aws_caller_identity.current.account_id
}

output "account_root_arn" {
  description = "Root principal ARN of the account, granted read access by the resource policy under test."
  value       = "arn:${local.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
}

output "tags" {
  description = "Identifying tags shared with the table under test."
  value       = local.tags
}
