mock_provider "aws" {}

variables {
  table_name = "orders"
  table = {
    read  = { min_capacity = 5, max_capacity = 100 }
    write = { min_capacity = 5, max_capacity = 50, target_utilization = 60, scale_in_cooldown = 600, scale_out_cooldown = 30 }
  }
  tags = { Environment = "test" }
}

run "registers_table_read_and_write_dimensions" {
  command = plan

  assert {
    condition     = length(aws_appautoscaling_target.this) == 2 && aws_appautoscaling_target.this["table_read"].resource_id == "table/orders" && aws_appautoscaling_target.this["table_read"].scalable_dimension == "dynamodb:table:ReadCapacityUnits" && aws_appautoscaling_target.this["table_read"].service_namespace == "dynamodb"
    error_message = "The table read target must address table/<name> on the DynamoDB read capacity dimension."
  }

  assert {
    condition     = aws_appautoscaling_target.this["table_write"].resource_id == "table/orders" && aws_appautoscaling_target.this["table_write"].scalable_dimension == "dynamodb:table:WriteCapacityUnits"
    error_message = "The table write target must address table/<name> on the DynamoDB write capacity dimension."
  }

  assert {
    condition     = aws_appautoscaling_target.this["table_read"].min_capacity == 5 && aws_appautoscaling_target.this["table_read"].max_capacity == 100 && aws_appautoscaling_target.this["table_write"].max_capacity == 50
    error_message = "Capacity bounds must pass through per dimension."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["table_read"].name == "orders-table_read" && aws_appautoscaling_policy.this["table_read"].policy_type == "TargetTrackingScaling" && aws_appautoscaling_policy.this["table_read"].resource_id == "table/orders" && aws_appautoscaling_policy.this["table_read"].scalable_dimension == "dynamodb:table:ReadCapacityUnits"
    error_message = "Policies must be target tracking, named <table>-<dimension>, and bound to their target."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["table_read"].target_tracking_scaling_policy_configuration[0].target_value == 70 && aws_appautoscaling_policy.this["table_read"].target_tracking_scaling_policy_configuration[0].scale_in_cooldown == 300 && aws_appautoscaling_policy.this["table_read"].target_tracking_scaling_policy_configuration[0].scale_out_cooldown == 60
    error_message = "A dimension must default to 70 percent utilisation with a 300 second scale-in and 60 second scale-out cooldown."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["table_read"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "DynamoDBReadCapacityUtilization" && aws_appautoscaling_policy.this["table_write"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "DynamoDBWriteCapacityUtilization"
    error_message = "Read and write dimensions must track their DynamoDB predefined utilisation metric."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["table_write"].target_tracking_scaling_policy_configuration[0].target_value == 60 && aws_appautoscaling_policy.this["table_write"].target_tracking_scaling_policy_configuration[0].scale_in_cooldown == 600 && aws_appautoscaling_policy.this["table_write"].target_tracking_scaling_policy_configuration[0].scale_out_cooldown == 30
    error_message = "Explicit utilisation targets and cooldowns must pass through."
  }

  assert {
    condition     = aws_appautoscaling_target.this["table_read"].tags["Environment"] == "test"
    error_message = "Caller tags must be applied to the scalable targets."
  }

  assert {
    condition     = length(output.target_resource_ids) == 2 && output.target_resource_ids["table_write"] == "table/orders" && length(output.policy_arns) == 2 && contains(keys(output.policy_arns), "table_read") && length(output.target_arns) == 2
    error_message = "Targets and policies must be exposed keyed by dimension."
  }
}

run "registers_index_dimensions" {
  command = plan

  variables {
    table = null
    indexes = {
      by_status   = { read = { min_capacity = 1, max_capacity = 10 }, write = { min_capacity = 1, max_capacity = 5 } }
      by_customer = { read = { min_capacity = 2, max_capacity = 20, target_utilization = 50 } }
    }
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 3 && aws_appautoscaling_target.this["index_by_status_read"].resource_id == "table/orders/index/by_status" && aws_appautoscaling_target.this["index_by_status_read"].scalable_dimension == "dynamodb:index:ReadCapacityUnits" && aws_appautoscaling_target.this["index_by_status_write"].scalable_dimension == "dynamodb:index:WriteCapacityUnits"
    error_message = "Index targets must address table/<name>/index/<index> on the DynamoDB index dimensions."
  }

  assert {
    condition     = aws_appautoscaling_target.this["index_by_customer_read"].min_capacity == 2 && aws_appautoscaling_target.this["index_by_customer_read"].max_capacity == 20 && aws_appautoscaling_policy.this["index_by_customer_read"].target_tracking_scaling_policy_configuration[0].target_value == 50
    error_message = "Index dimensions must carry their own bounds and target."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["index_by_status_write"].name == "orders-index_by_status_write" && aws_appautoscaling_policy.this["index_by_status_write"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "DynamoDBWriteCapacityUtilization"
    error_message = "Index policies must be named after the table and dimension and track the write metric."
  }

  assert {
    condition     = length(output.policy_arns) == 3 && contains(keys(output.policy_arns), "index_by_customer_read") && !contains(keys(output.target_resource_ids), "table_read")
    error_message = "Only declared dimensions may be exposed."
  }
}

run "scales_only_declared_dimensions" {
  command = plan

  variables {
    table = { read = { min_capacity = 1, max_capacity = 10 } }
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 1 && contains(keys(aws_appautoscaling_target.this), "table_read") && length(aws_appautoscaling_policy.this) == 1
    error_message = "An undeclared write dimension must not be scaled."
  }
}

run "rejects_min_above_max" {
  command = plan

  variables {
    table = { read = { min_capacity = 11, max_capacity = 10 } }
  }

  expect_failures = [var.table]
}

run "rejects_zero_min_capacity" {
  command = plan

  variables {
    table = { write = { min_capacity = 0, max_capacity = 10 } }
  }

  expect_failures = [var.table]
}

run "rejects_target_outside_range" {
  command = plan

  variables {
    table = { read = { min_capacity = 1, max_capacity = 10, target_utilization = 95 } }
  }

  expect_failures = [var.table]
}

run "rejects_negative_cooldown" {
  command = plan

  variables {
    table = { read = { min_capacity = 1, max_capacity = 10, scale_in_cooldown = -1 } }
  }

  expect_failures = [var.table]
}

run "rejects_index_min_above_max" {
  command = plan

  variables {
    indexes = { by_status = { read = { min_capacity = 5, max_capacity = 1 } } }
  }

  expect_failures = [var.indexes]
}

run "rejects_index_with_no_dimension" {
  command = plan

  variables {
    indexes = { by_status = {} }
  }

  expect_failures = [var.indexes]
}

run "rejects_invalid_table_name" {
  command = plan

  variables {
    table_name = "no spaces"
  }

  expect_failures = [var.table_name]
}

run "rejects_no_scaled_dimension" {
  command = plan

  variables {
    table   = null
    indexes = {}
  }

  expect_failures = [output.target_resource_ids]
}
