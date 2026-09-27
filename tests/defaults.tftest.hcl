mock_provider "aws" {}

variables {
  name       = "orders"
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S" }
  tags       = { Environment = "test", Owner = "platform" }
}

run "table_is_on_demand_encrypted_recoverable_and_protected" {
  command = plan

  assert {
    condition     = length(aws_dynamodb_table.this) == 1 && length(aws_dynamodb_table.autoscaled) == 0
    error_message = "Without autoscaling only the plain table variant may exist."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].name == "orders" && aws_dynamodb_table.this[0].hash_key == "pk" && aws_dynamodb_table.this[0].range_key == "sk" && length(aws_dynamodb_table.this[0].attribute) == 2
    error_message = "The table must use the declared name, keys, and attribute definitions."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].billing_mode == "PAY_PER_REQUEST" && aws_dynamodb_table.this[0].table_class == "STANDARD"
    error_message = "Tables must default to on-demand billing in the STANDARD class."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].deletion_protection_enabled == true && aws_dynamodb_table.this[0].point_in_time_recovery[0].enabled == true && aws_dynamodb_table.this[0].server_side_encryption[0].enabled == true
    error_message = "Deletion protection, point-in-time recovery, and encryption at rest must be on by default."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].stream_enabled == false && length(aws_dynamodb_table.this[0].ttl) == 0 && length(aws_dynamodb_table.this[0].replica) == 0 && length(aws_dynamodb_table.this[0].on_demand_throughput) == 0
    error_message = "Streams, TTL, replicas, and on-demand limits must not render unless declared."
  }

  assert {
    condition     = length(aws_dynamodb_table.this[0].global_secondary_index) == 0 && length(aws_dynamodb_table.this[0].local_secondary_index) == 0
    error_message = "No index may render unless declared."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].tags["Name"] == "orders" && aws_dynamodb_table.this[0].tags["Owner"] == "platform" && aws_dynamodb_table.this[0].tags["Environment"] == "test"
    error_message = "Caller tags must be preserved and a Name tag added."
  }

  assert {
    condition     = length(aws_dynamodb_resource_policy.this) == 0 && length(aws_dynamodb_contributor_insights.this) == 0 && length(aws_dynamodb_contributor_insights.index) == 0 && length(aws_dynamodb_kinesis_streaming_destination.this) == 0 && length(module.autoscaling) == 0
    error_message = "No helper resource may be created unless declared."
  }
}

run "outputs_expose_configured_identity" {
  command = plan

  assert {
    condition     = output.name == "orders" && output.hash_key == "pk" && output.range_key == "sk" && output.billing_mode == "PAY_PER_REQUEST" && output.table_class == "STANDARD"
    error_message = "Outputs must expose the configured identity and key schema."
  }

  assert {
    condition     = length(output.global_secondary_index_arns) == 0 && length(output.local_secondary_index_arns) == 0 && length(output.replica_arns) == 0
    error_message = "Index and replica ARN maps must be empty when none are declared."
  }

  assert {
    condition     = length(output.autoscaling_target_resource_ids) == 0 && length(output.autoscaling_policy_arns) == 0 && output.resource_policy == null && output.stream_arn == null && output.stream_label == null
    error_message = "Autoscaling, resource policy, and stream outputs must be empty when those features are off."
  }
}

run "warns_when_deletion_protection_is_disabled" {
  command = plan

  variables {
    deletion_protection_enabled = false
  }

  expect_failures = [check.deletion_protection_disabled]
}

run "warns_when_point_in_time_recovery_is_disabled" {
  command = plan

  variables {
    point_in_time_recovery = { enabled = false }
  }

  expect_failures = [check.point_in_time_recovery_disabled]
}
