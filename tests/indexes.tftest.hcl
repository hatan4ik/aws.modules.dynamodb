mock_provider "aws" {}

variables {
  name       = "orders"
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S", status = "S", created_at = "N" }
}

run "renders_global_and_local_secondary_indexes" {
  command = plan

  variables {
    global_secondary_indexes = {
      by_status  = { hash_key = "status", range_key = "created_at", projection_type = "ALL" }
      by_created = { hash_key = "created_at", projection_type = "INCLUDE", non_key_attributes = ["status"] }
    }
    local_secondary_indexes = {
      by_created_in_partition = { range_key = "created_at", projection_type = "KEYS_ONLY" }
    }
  }

  assert {
    condition     = length([for index in aws_dynamodb_table.this[0].global_secondary_index : index.name]) == 2 && length(aws_dynamodb_table.this[0].attribute) == 4
    error_message = "Every declared GSI and attribute must render."
  }

  assert {
    condition     = one([for index in aws_dynamodb_table.this[0].global_secondary_index : index.projection_type if index.name == "by_status"]) == "ALL" && one([for index in aws_dynamodb_table.this[0].global_secondary_index : index.range_key if index.name == "by_status"]) == "created_at"
    error_message = "A GSI must carry its declared keys and projection."
  }

  assert {
    condition     = contains(one([for index in aws_dynamodb_table.this[0].global_secondary_index : index.non_key_attributes if index.name == "by_created"]), "status") && one([for index in aws_dynamodb_table.this[0].global_secondary_index : index.range_key if index.name == "by_created"]) == null
    error_message = "An INCLUDE projection must carry its non-key attributes and a hash-only GSI no range key."
  }

  assert {
    condition     = length([for index in aws_dynamodb_table.this[0].local_secondary_index : index.name]) == 1 && one([for index in aws_dynamodb_table.this[0].local_secondary_index : index.range_key]) == "created_at" && one([for index in aws_dynamodb_table.this[0].local_secondary_index : index.projection_type]) == "KEYS_ONLY"
    error_message = "An LSI must render with its range key and projection."
  }

  assert {
    condition     = length(output.global_secondary_index_arns) == 2 && contains(keys(output.global_secondary_index_arns), "by_status") && contains(keys(output.global_secondary_index_arns), "by_created") && length(output.local_secondary_index_arns) == 1 && contains(keys(output.local_secondary_index_arns), "by_created_in_partition")
    error_message = "Index ARN maps must be keyed by index name."
  }
}

run "renders_on_demand_throughput_limits" {
  command = plan

  variables {
    on_demand_throughput = { max_read_request_units = 1000, max_write_request_units = 500 }
    global_secondary_indexes = {
      by_status = { hash_key = "status", range_key = "created_at", projection_type = "KEYS_ONLY", on_demand_throughput = { max_read_request_units = -1, max_write_request_units = 100 } }
    }
  }

  assert {
    condition     = aws_dynamodb_table.this[0].on_demand_throughput[0].max_read_request_units == 1000 && aws_dynamodb_table.this[0].on_demand_throughput[0].max_write_request_units == 500
    error_message = "Table on-demand limits must pass through."
  }

  assert {
    condition     = one([for index in aws_dynamodb_table.this[0].global_secondary_index : index.on_demand_throughput[0].max_write_request_units if index.name == "by_status"]) == 100 && one([for index in aws_dynamodb_table.this[0].global_secondary_index : index.on_demand_throughput[0].max_read_request_units if index.name == "by_status"]) == -1
    error_message = "GSI on-demand limits must pass through, including -1 to remove a limit."
  }
}

run "renders_provisioned_capacities" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 10
    write_capacity = 5
    global_secondary_indexes = {
      by_status = { hash_key = "status", range_key = "created_at", projection_type = "ALL", read_capacity = 3, write_capacity = 2 }
    }
  }

  assert {
    condition     = aws_dynamodb_table.this[0].billing_mode == "PROVISIONED" && aws_dynamodb_table.this[0].read_capacity == 10 && aws_dynamodb_table.this[0].write_capacity == 5
    error_message = "Provisioned table capacities must pass through."
  }

  assert {
    condition     = one([for index in aws_dynamodb_table.this[0].global_secondary_index : index.read_capacity if index.name == "by_status"]) == 3 && one([for index in aws_dynamodb_table.this[0].global_secondary_index : index.write_capacity if index.name == "by_status"]) == 2
    error_message = "Provisioned GSI capacities must pass through."
  }
}
