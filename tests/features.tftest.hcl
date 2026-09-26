mock_provider "aws" {}

variables {
  name       = "orders"
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S" }
}

run "renders_ttl_stream_class_recovery_window_and_customer_key" {
  command = plan

  variables {
    ttl                    = { attribute_name = "expires_at" }
    stream                 = { view_type = "NEW_AND_OLD_IMAGES" }
    table_class            = "STANDARD_INFREQUENT_ACCESS"
    point_in_time_recovery = { recovery_period_in_days = 14 }
    server_side_encryption = { kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111" }
    timeouts               = { create = "30m", delete = "20m" }
  }

  assert {
    condition     = aws_dynamodb_table.this[0].ttl[0].enabled == true && aws_dynamodb_table.this[0].ttl[0].attribute_name == "expires_at"
    error_message = "TTL must render enabled on the declared attribute."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].stream_enabled == true && aws_dynamodb_table.this[0].stream_view_type == "NEW_AND_OLD_IMAGES"
    error_message = "A declared stream must be enabled with its view type."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].table_class == "STANDARD_INFREQUENT_ACCESS" && aws_dynamodb_table.this[0].point_in_time_recovery[0].enabled == true && aws_dynamodb_table.this[0].point_in_time_recovery[0].recovery_period_in_days == 14
    error_message = "Table class and the recovery window must pass through."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].server_side_encryption[0].enabled == true && aws_dynamodb_table.this[0].server_side_encryption[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"
    error_message = "A customer managed key must be applied with encryption still enabled."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].timeouts.create == "30m" && aws_dynamodb_table.this[0].timeouts.delete == "20m" && aws_dynamodb_table.this[0].timeouts.update == null
    error_message = "Timeouts must pass through unchanged."
  }
}

run "disables_ttl_without_an_attribute_name" {
  command = plan

  variables {
    ttl = { attribute_name = "expires_at", enabled = false }
  }

  assert {
    condition     = aws_dynamodb_table.this[0].ttl[0].enabled == false && aws_dynamodb_table.this[0].ttl[0].attribute_name == null
    error_message = "A disabled TTL must render without an attribute name, as the provider requires."
  }
}

run "attaches_contributor_insights_to_table_and_indexes" {
  command = plan

  variables {
    attributes                   = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes     = { by_status = { hash_key = "status", projection_type = "KEYS_ONLY" } }
    contributor_insights_enabled = true
    contributor_insights_indexes = ["by_status"]
  }

  assert {
    condition     = length(aws_dynamodb_contributor_insights.this) == 1 && aws_dynamodb_contributor_insights.this[0].table_name == "orders" && aws_dynamodb_contributor_insights.this[0].index_name == null
    error_message = "Table-level Contributor Insights must target the table only."
  }

  assert {
    condition     = length(aws_dynamodb_contributor_insights.index) == 1 && aws_dynamodb_contributor_insights.index["by_status"].table_name == "orders" && aws_dynamodb_contributor_insights.index["by_status"].index_name == "by_status"
    error_message = "Index-level Contributor Insights must target the named GSI."
  }
}

run "attaches_kinesis_streaming_destination" {
  command = plan

  variables {
    kinesis_stream_arn                               = "arn:aws:kinesis:us-east-1:123456789012:stream/orders-changes"
    kinesis_approximate_creation_date_time_precision = "MICROSECOND"
  }

  assert {
    condition     = length(aws_dynamodb_kinesis_streaming_destination.this) == 1 && aws_dynamodb_kinesis_streaming_destination.this[0].table_name == "orders" && aws_dynamodb_kinesis_streaming_destination.this[0].stream_arn == "arn:aws:kinesis:us-east-1:123456789012:stream/orders-changes" && aws_dynamodb_kinesis_streaming_destination.this[0].approximate_creation_date_time_precision == "MICROSECOND"
    error_message = "The Kinesis destination must target the table and the named stream with the declared precision."
  }
}
