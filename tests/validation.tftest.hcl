mock_provider "aws" {}

variables {
  name       = "orders"
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S" }
}

run "rejects_name_with_invalid_characters" {
  command = plan

  variables {
    name = "orders table"
  }

  expect_failures = [var.name]
}

run "rejects_name_shorter_than_three_characters" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "rejects_unknown_attribute_type" {
  command = plan

  variables {
    attributes = { pk = "S", sk = "X" }
  }

  expect_failures = [var.attributes]
}

run "rejects_empty_attribute_map" {
  command = plan

  variables {
    attributes = {}
  }

  expect_failures = [var.attributes]
}

run "rejects_unknown_billing_mode" {
  command = plan

  variables {
    billing_mode = "ON_DEMAND"
  }

  expect_failures = [var.billing_mode]
}

run "rejects_zero_read_capacity" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 0
    write_capacity = 5
  }

  expect_failures = [var.read_capacity]
}

run "rejects_zero_write_capacity" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 5
    write_capacity = 0
  }

  expect_failures = [var.write_capacity]
}

run "rejects_unknown_table_class" {
  command = plan

  variables {
    table_class = "GLACIER"
  }

  expect_failures = [var.table_class]
}

run "rejects_on_demand_limit_below_one" {
  command = plan

  variables {
    on_demand_throughput = { max_read_request_units = 0 }
  }

  expect_failures = [var.on_demand_throughput]
}

run "rejects_on_demand_throughput_without_limits" {
  command = plan

  variables {
    on_demand_throughput = {}
  }

  expect_failures = [var.on_demand_throughput]
}

run "rejects_gsi_include_projection_without_non_key_attributes" {
  command = plan

  variables {
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "INCLUDE" } }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_gsi_keys_only_projection_with_non_key_attributes" {
  command = plan

  variables {
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "KEYS_ONLY", non_key_attributes = ["sk"] } }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_gsi_with_identical_hash_and_range_key" {
  command = plan

  variables {
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", range_key = "status", projection_type = "ALL" } }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_gsi_with_invalid_name" {
  command = plan

  variables {
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { "by status" = { hash_key = "status", projection_type = "ALL" } }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_gsi_with_unknown_projection_type" {
  command = plan

  variables {
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "SOME" } }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_gsi_with_zero_capacity" {
  command = plan

  variables {
    billing_mode             = "PROVISIONED"
    read_capacity            = 5
    write_capacity           = 5
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "ALL", read_capacity = 0, write_capacity = 1 } }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_gsi_on_demand_limit_below_one" {
  command = plan

  variables {
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "ALL", on_demand_throughput = { max_write_request_units = 0 } } }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_lsi_include_projection_without_non_key_attributes" {
  command = plan

  variables {
    attributes              = { pk = "S", sk = "S", created_at = "N" }
    local_secondary_indexes = { by_created = { range_key = "created_at", projection_type = "INCLUDE" } }
  }

  expect_failures = [var.local_secondary_indexes]
}

run "rejects_lsi_with_invalid_name" {
  command = plan

  variables {
    attributes              = { pk = "S", sk = "S", created_at = "N" }
    local_secondary_indexes = { "by created" = { range_key = "created_at", projection_type = "ALL" } }
  }

  expect_failures = [var.local_secondary_indexes]
}

run "rejects_more_than_five_lsis" {
  command = plan

  variables {
    attributes              = { pk = "S", sk = "S", a = "N", b = "N", c = "N", d = "N", e = "N", f = "N" }
    local_secondary_indexes = { by_a = { range_key = "a", projection_type = "ALL" }, by_b = { range_key = "b", projection_type = "ALL" }, by_c = { range_key = "c", projection_type = "ALL" }, by_d = { range_key = "d", projection_type = "ALL" }, by_e = { range_key = "e", projection_type = "ALL" }, by_f = { range_key = "f", projection_type = "ALL" } }
  }

  expect_failures = [var.local_secondary_indexes]
}

run "rejects_ttl_with_empty_attribute_name" {
  command = plan

  variables {
    ttl = { attribute_name = "" }
  }

  expect_failures = [var.ttl]
}

run "rejects_recovery_period_outside_range" {
  command = plan

  variables {
    point_in_time_recovery = { recovery_period_in_days = 40 }
  }

  expect_failures = [var.point_in_time_recovery]
}

run "rejects_recovery_period_when_recovery_is_disabled" {
  command = plan

  variables {
    point_in_time_recovery = { enabled = false, recovery_period_in_days = 7 }
  }

  expect_failures = [var.point_in_time_recovery]
}

run "rejects_malformed_kms_key_arn" {
  command = plan

  variables {
    server_side_encryption = { kms_key_arn = "alias/orders" }
  }

  expect_failures = [var.server_side_encryption]
}

run "rejects_unknown_stream_view_type" {
  command = plan

  variables {
    stream = { view_type = "IMAGES" }
  }

  expect_failures = [var.stream]
}

run "rejects_malformed_replica_region" {
  command = plan

  variables {
    stream   = { view_type = "NEW_AND_OLD_IMAGES" }
    replicas = { europe = {} }
  }

  expect_failures = [var.replicas]
}

run "rejects_malformed_replica_kms_key_arn" {
  command = plan

  variables {
    stream   = { view_type = "NEW_AND_OLD_IMAGES" }
    replicas = { "eu-west-1" = { kms_key_arn = "alias/orders" } }
  }

  expect_failures = [var.replicas]
}

run "rejects_unknown_replica_consistency_mode" {
  command = plan

  variables {
    stream   = { view_type = "NEW_AND_OLD_IMAGES" }
    replicas = { "eu-west-1" = { consistency_mode = "WEAK" } }
  }

  expect_failures = [var.replicas]
}

run "rejects_malformed_kinesis_stream_arn" {
  command = plan

  variables {
    kinesis_stream_arn = "orders-changes"
  }

  expect_failures = [var.kinesis_stream_arn]
}

run "rejects_unknown_kinesis_precision" {
  command = plan

  variables {
    kinesis_stream_arn                               = "arn:aws:kinesis:us-east-1:123456789012:stream/orders-changes"
    kinesis_approximate_creation_date_time_precision = "NANOSECOND"
  }

  expect_failures = [var.kinesis_approximate_creation_date_time_precision]
}

run "rejects_policy_statement_with_non_alphanumeric_sid" {
  command = plan

  variables {
    resource_policy_statements = { "read-only" = { principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }, actions = ["dynamodb:GetItem"] } }
  }

  expect_failures = [var.resource_policy_statements]
}

run "rejects_policy_statement_with_unknown_effect" {
  command = plan

  variables {
    resource_policy_statements = { ReadOnly = { effect = "Permit", principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }, actions = ["dynamodb:GetItem"] } }
  }

  expect_failures = [var.resource_policy_statements]
}

run "rejects_policy_statement_with_unknown_principal_type" {
  command = plan

  variables {
    resource_policy_statements = { ReadOnly = { principals = { IAM = ["arn:aws:iam::123456789012:role/reader"] }, actions = ["dynamodb:GetItem"] } }
  }

  expect_failures = [var.resource_policy_statements]
}

run "rejects_policy_statement_with_wildcard_principal_and_no_condition" {
  command = plan

  variables {
    resource_policy_statements = { ReadOnly = { principals = { AWS = ["*"] }, actions = ["dynamodb:GetItem"] } }
  }

  expect_failures = [var.resource_policy_statements]
}

run "rejects_policy_statement_without_actions" {
  command = plan

  variables {
    resource_policy_statements = { ReadOnly = { principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }, actions = [] } }
  }

  expect_failures = [var.resource_policy_statements]
}

run "rejects_policy_statement_without_principals" {
  command = plan

  variables {
    resource_policy_statements = { ReadOnly = { principals = {}, actions = ["dynamodb:GetItem"] } }
  }

  expect_failures = [var.resource_policy_statements]
}

run "rejects_policy_statement_with_duplicate_condition_keys" {
  command = plan

  variables {
    resource_policy_statements = { ReadOnly = { principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }, actions = ["dynamodb:GetItem"], conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["true"] }, { test = "Bool", variable = "aws:SecureTransport", values = ["false"] }] } }
  }

  expect_failures = [var.resource_policy_statements]
}

run "rejects_autoscaling_without_dimensions" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
    autoscaling  = {}
  }

  expect_failures = [var.autoscaling]
}

run "rejects_autoscaling_min_above_max" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
    autoscaling  = { table = { read = { min_capacity = 10, max_capacity = 1 } } }
  }

  expect_failures = [var.autoscaling]
}

run "rejects_autoscaling_target_outside_range" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
    autoscaling  = { table = { write = { min_capacity = 1, max_capacity = 10, target_utilization = 10 } } }
  }

  expect_failures = [var.autoscaling]
}

run "rejects_autoscaling_index_without_dimensions" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 5
    write_capacity = 5
    autoscaling    = { indexes = { by_status = {} } }
  }

  expect_failures = [var.autoscaling]
}

run "rejects_undeclared_key_attribute" {
  command = plan

  variables {
    attributes = { pk = "S" }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_unused_attribute" {
  command = plan

  variables {
    attributes = { pk = "S", sk = "S", extra = "N" }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_range_key_equal_to_hash_key" {
  command = plan

  variables {
    range_key  = "pk"
    attributes = { pk = "S" }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_gsi_with_undeclared_key_attribute" {
  command = plan

  variables {
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "ALL" } }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_lsi_with_undeclared_key_attribute" {
  command = plan

  variables {
    local_secondary_indexes = { by_created = { range_key = "created_at", projection_type = "ALL" } }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_lsi_without_table_range_key" {
  command = plan

  variables {
    range_key               = null
    attributes              = { pk = "S", created_at = "N" }
    local_secondary_indexes = { by_created = { range_key = "created_at", projection_type = "ALL" } }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_gsi_and_lsi_sharing_a_name" {
  command = plan

  variables {
    attributes               = { pk = "S", sk = "S", status = "S", created_at = "N" }
    global_secondary_indexes = { by_time = { hash_key = "status", projection_type = "ALL" } }
    local_secondary_indexes  = { by_time = { range_key = "created_at", projection_type = "ALL" } }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_ttl_on_a_key_attribute" {
  command = plan

  variables {
    ttl = { attribute_name = "sk" }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_provisioned_table_without_capacity" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_provisioned_gsi_without_capacity" {
  command = plan

  variables {
    billing_mode             = "PROVISIONED"
    read_capacity            = 5
    write_capacity           = 5
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "ALL" } }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_capacity_on_an_on_demand_table" {
  command = plan

  variables {
    read_capacity  = 5
    write_capacity = 5
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_gsi_capacity_on_an_on_demand_table" {
  command = plan

  variables {
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "ALL", read_capacity = 1, write_capacity = 1 } }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_on_demand_throughput_on_a_provisioned_table" {
  command = plan

  variables {
    billing_mode         = "PROVISIONED"
    read_capacity        = 5
    write_capacity       = 5
    on_demand_throughput = { max_read_request_units = 100 }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_gsi_on_demand_throughput_on_a_provisioned_table" {
  command = plan

  variables {
    billing_mode             = "PROVISIONED"
    read_capacity            = 5
    write_capacity           = 5
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "ALL", read_capacity = 1, write_capacity = 1, on_demand_throughput = { max_read_request_units = 100 } } }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_autoscaling_on_an_on_demand_table" {
  command = plan

  variables {
    autoscaling = { table = { read = { min_capacity = 1, max_capacity = 10 } } }
  }

  expect_failures = [aws_dynamodb_table.autoscaled]
}

run "rejects_autoscaling_for_an_undeclared_index" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 5
    write_capacity = 5
    autoscaling    = { indexes = { missing = { read = { min_capacity = 1, max_capacity = 10 } } } }
  }

  expect_failures = [aws_dynamodb_table.autoscaled]
}

run "rejects_explicit_capacity_outside_autoscaling_bounds" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 50
    write_capacity = 5
    autoscaling    = { table = { read = { min_capacity = 1, max_capacity = 10 } } }
  }

  expect_failures = [aws_dynamodb_table.autoscaled]
}

run "rejects_explicit_gsi_capacity_outside_autoscaling_bounds" {
  command = plan

  variables {
    billing_mode             = "PROVISIONED"
    read_capacity            = 5
    write_capacity           = 5
    attributes               = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "ALL", read_capacity = 50, write_capacity = 1 } }
    autoscaling              = { indexes = { by_status = { read = { min_capacity = 1, max_capacity = 10 }, write = { min_capacity = 1, max_capacity = 10 } } } }
  }

  expect_failures = [aws_dynamodb_table.autoscaled]
}

run "rejects_replicas_without_a_stream" {
  command = plan

  variables {
    replicas = { "eu-west-1" = {} }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_replicas_with_a_partial_stream_view" {
  command = plan

  variables {
    stream   = { view_type = "NEW_IMAGE" }
    replicas = { "eu-west-1" = {} }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_replicas_on_a_provisioned_table_without_autoscaling" {
  command = plan

  variables {
    billing_mode   = "PROVISIONED"
    read_capacity  = 5
    write_capacity = 5
    stream         = { view_type = "NEW_AND_OLD_IMAGES" }
    replicas       = { "eu-west-1" = {} }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_replica_without_a_key_when_the_table_uses_a_customer_key" {
  command = plan

  variables {
    server_side_encryption = { kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111" }
    stream                 = { view_type = "NEW_AND_OLD_IMAGES" }
    replicas               = { "eu-west-1" = {} }
  }

  expect_failures = [aws_dynamodb_table.this]
}

run "rejects_contributor_insights_for_an_undeclared_index" {
  command = plan

  variables {
    contributor_insights_indexes = ["missing"]
  }

  expect_failures = [aws_dynamodb_table.this]
}
