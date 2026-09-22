resource "terraform_data" "input_contract" {
  input = {
    billing_mode   = var.billing_mode
    read_capacity  = var.read_capacity
    write_capacity = var.write_capacity
  }

  lifecycle {
    precondition {
      condition     = var.billing_mode == "PAY_PER_REQUEST" || (var.read_capacity != null && var.write_capacity != null)
      error_message = "PROVISIONED tables require read_capacity and write_capacity."
    }
    precondition {
      condition     = contains(keys(var.attributes), var.hash_key) && (var.range_key == null || contains(keys(var.attributes), var.range_key))
      error_message = "attributes must include the primary key attributes."
    }
  }
}

resource "aws_dynamodb_table" "this" {
  name                        = var.name
  billing_mode                = var.billing_mode
  hash_key                    = var.hash_key
  range_key                   = var.range_key
  read_capacity               = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity              = var.billing_mode == "PROVISIONED" ? var.write_capacity : null
  deletion_protection_enabled = var.deletion_protection_enabled

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.key
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name               = global_secondary_index.key
      hash_key           = global_secondary_index.value.hash_key
      range_key          = global_secondary_index.value.range_key
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.non_key_attributes
      read_capacity      = var.billing_mode == "PROVISIONED" ? global_secondary_index.value.read_capacity : null
      write_capacity     = var.billing_mode == "PROVISIONED" ? global_secondary_index.value.write_capacity : null
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  ttl {
    enabled        = var.ttl_attribute_name != null
    attribute_name = var.ttl_attribute_name
  }

  tags = var.tags
}
