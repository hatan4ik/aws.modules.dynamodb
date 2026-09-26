mock_provider "aws" {}

variables {
  name         = "orders"
  hash_key     = "pk"
  range_key    = "sk"
  attributes   = { pk = "S", sk = "S" }
  billing_mode = "PROVISIONED"
}

run "selects_the_autoscaled_variant_and_derives_initial_capacity" {
  command = plan

  variables {
    autoscaling = {
      table = {
        read  = { min_capacity = 5, max_capacity = 100 }
        write = { min_capacity = 2, max_capacity = 50 }
      }
    }
  }

  assert {
    condition     = length(aws_dynamodb_table.this) == 0 && length(aws_dynamodb_table.autoscaled) == 1 && aws_dynamodb_table.autoscaled[0].name == "orders" && aws_dynamodb_table.autoscaled[0].billing_mode == "PROVISIONED"
    error_message = "Only the autoscaled table variant may exist when autoscaling is declared."
  }

  assert {
    condition     = aws_dynamodb_table.autoscaled[0].read_capacity == 5 && aws_dynamodb_table.autoscaled[0].write_capacity == 2
    error_message = "An autoscaled dimension without an explicit capacity must start at its minimum."
  }

  assert {
    condition     = output.name == "orders" && output.billing_mode == "PROVISIONED"
    error_message = "Outputs must resolve from whichever table variant exists."
  }

  assert {
    condition     = length(module.autoscaling) == 1 && length(output.autoscaling_target_resource_ids) == 2 && output.autoscaling_target_resource_ids["table_read"] == "table/orders" && output.autoscaling_target_resource_ids["table_write"] == "table/orders" && length(output.autoscaling_policy_arns) == 2
    error_message = "Autoscaling targets and policies must be exposed keyed by dimension."
  }
}

run "scales_indexes_and_keeps_explicit_capacities" {
  command = plan

  variables {
    read_capacity  = 10
    write_capacity = 10
    attributes     = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = {
      by_status = { hash_key = "status", projection_type = "KEYS_ONLY" }
    }
    autoscaling = {
      table   = { read = { min_capacity = 5, max_capacity = 100 } }
      indexes = { by_status = { read = { min_capacity = 1, max_capacity = 10 }, write = { min_capacity = 3, max_capacity = 30 } } }
    }
  }

  assert {
    condition     = aws_dynamodb_table.autoscaled[0].read_capacity == 10 && aws_dynamodb_table.autoscaled[0].write_capacity == 10
    error_message = "Explicit capacities within the autoscaling bounds must be kept as the initial values."
  }

  assert {
    condition     = one([for index in aws_dynamodb_table.autoscaled[0].global_secondary_index : index.read_capacity if index.name == "by_status"]) == 1 && one([for index in aws_dynamodb_table.autoscaled[0].global_secondary_index : index.write_capacity if index.name == "by_status"]) == 3
    error_message = "An autoscaled GSI without explicit capacities must start at its minimums."
  }

  assert {
    condition     = length(output.autoscaling_target_resource_ids) == 3 && output.autoscaling_target_resource_ids["index_by_status_read"] == "table/orders/index/by_status" && output.autoscaling_target_resource_ids["index_by_status_write"] == "table/orders/index/by_status"
    error_message = "Index dimensions must be exposed with their index resource ID."
  }
}
