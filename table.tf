# Terraform cannot make lifecycle.ignore_changes conditional, so two table
# resources exist and exactly one is created. Keep their bodies identical;
# only count and the ignore_changes list differ. scripts/check-resource-variants.sh
# enforces this in make check and pre-commit.
#
# The autoscaled variant ignores read_capacity, write_capacity, and
# global_secondary_index: Application Auto Scaling owns the capacities after
# creation, and global_secondary_index is a set, so its capacities cannot be
# ignored individually.
#
# checkov:skip=CKV_AWS_119 is applied inline on both variants: encryption at
# rest is always enabled and the AWS owned key is the deliberate default when
# server_side_encryption.kms_key_arn is null (README, Security model).

resource "aws_dynamodb_table" "this" {
  count = var.autoscaling == null ? 1 : 0

  # checkov:skip=CKV_AWS_119: Encryption is always enabled; the AWS owned key is the deliberate default and server_side_encryption.kms_key_arn selects a customer managed key.

  name                        = var.name
  billing_mode                = var.billing_mode
  hash_key                    = var.hash_key
  range_key                   = var.range_key
  read_capacity               = local.read_capacity
  write_capacity              = local.write_capacity
  table_class                 = var.table_class
  deletion_protection_enabled = var.deletion_protection_enabled
  stream_enabled              = var.stream != null
  stream_view_type            = var.stream == null ? null : var.stream.view_type

  dynamic "attribute" {
    for_each = var.attributes

    content {
      name = attribute.key
      type = attribute.value
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
      read_capacity      = local.gsi_capacities[global_secondary_index.key].read
      write_capacity     = local.gsi_capacities[global_secondary_index.key].write

      dynamic "on_demand_throughput" {
        for_each = global_secondary_index.value.on_demand_throughput == null ? [] : [global_secondary_index.value.on_demand_throughput]

        content {
          max_read_request_units  = on_demand_throughput.value.max_read_request_units
          max_write_request_units = on_demand_throughput.value.max_write_request_units
        }
      }
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_indexes

    content {
      name               = local_secondary_index.key
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.non_key_attributes
    }
  }

  dynamic "on_demand_throughput" {
    for_each = var.on_demand_throughput == null ? [] : [var.on_demand_throughput]

    content {
      max_read_request_units  = on_demand_throughput.value.max_read_request_units
      max_write_request_units = on_demand_throughput.value.max_write_request_units
    }
  }

  dynamic "replica" {
    for_each = var.replicas

    content {
      region_name                 = replica.key
      kms_key_arn                 = replica.value.kms_key_arn
      point_in_time_recovery      = replica.value.point_in_time_recovery == null ? var.point_in_time_recovery.enabled : replica.value.point_in_time_recovery
      propagate_tags              = replica.value.propagate_tags
      deletion_protection_enabled = replica.value.deletion_protection_enabled == null ? var.deletion_protection_enabled : replica.value.deletion_protection_enabled
      consistency_mode            = replica.value.consistency_mode
    }
  }

  point_in_time_recovery {
    enabled                 = var.point_in_time_recovery.enabled
    recovery_period_in_days = var.point_in_time_recovery.recovery_period_in_days
  }

  # Encryption at rest is always on. The AWS owned key is the deliberate
  # default; server_side_encryption.kms_key_arn selects a customer managed key.
  # See README, Security model.
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.server_side_encryption.kms_key_arn
  }

  dynamic "ttl" {
    for_each = var.ttl == null ? [] : [var.ttl]

    content {
      enabled        = ttl.value.enabled
      attribute_name = ttl.value.enabled ? ttl.value.attribute_name : null
    }
  }

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = length(local.undeclared_key_attributes) == 0
      error_message = "Every key attribute must be declared in attributes. Undeclared: ${join(", ", local.undeclared_key_attributes)}."
    }

    precondition {
      condition     = length(local.unused_attributes) == 0
      error_message = "DynamoDB rejects attribute definitions that no key uses. Remove from attributes or use in a key: ${join(", ", local.unused_attributes)}."
    }

    precondition {
      condition     = var.range_key == null ? true : var.hash_key != var.range_key
      error_message = "range_key must differ from hash_key."
    }

    precondition {
      condition     = length(local.duplicate_index_names) == 0
      error_message = "Global and local secondary index names must be unique across both maps. Duplicated: ${join(", ", local.duplicate_index_names)}."
    }

    precondition {
      condition     = length(var.local_secondary_indexes) == 0 || var.range_key != null
      error_message = "local_secondary_indexes require the table to have a range_key."
    }

    precondition {
      condition     = var.ttl == null ? true : !contains(local.key_attributes, var.ttl.attribute_name)
      error_message = "ttl.attribute_name must not be a key attribute of the table or of an index."
    }

    precondition {
      condition     = !local.provisioned || (local.read_capacity != null && local.write_capacity != null)
      error_message = "A PROVISIONED table needs read_capacity and write_capacity, or an autoscaling.table dimension for each."
    }

    precondition {
      condition     = !local.provisioned || length(local.gsis_without_capacity) == 0
      error_message = "Every GSI of a PROVISIONED table needs read_capacity and write_capacity, or an autoscaling.indexes dimension for each. Missing on: ${join(", ", local.gsis_without_capacity)}."
    }

    precondition {
      condition     = length(local.capacities_outside_bounds) == 0
      error_message = "An explicit capacity on an autoscaled dimension is its initial value and must lie within min_capacity and max_capacity. Outside bounds: ${join(", ", local.capacities_outside_bounds)}."
    }

    precondition {
      condition     = local.provisioned || (var.read_capacity == null && var.write_capacity == null && length(local.on_demand_gsis_with_capacity) == 0)
      error_message = "A PAY_PER_REQUEST table cannot set read_capacity or write_capacity on the table or on a GSI. Set billing_mode = \"PROVISIONED\" or remove the capacities."
    }

    precondition {
      condition     = local.provisioned || var.autoscaling == null
      error_message = "autoscaling applies to PROVISIONED tables only. On-demand tables scale on their own; use on_demand_throughput to cap them."
    }

    precondition {
      condition     = !local.provisioned || (var.on_demand_throughput == null && length(local.provisioned_gsis_with_on_demand) == 0)
      error_message = "on_demand_throughput on the table or a GSI requires billing_mode = \"PAY_PER_REQUEST\"."
    }

    precondition {
      condition     = length(local.undeclared_autoscaled_indexes) == 0
      error_message = "autoscaling.indexes must name keys of global_secondary_indexes. Undeclared: ${join(", ", local.undeclared_autoscaled_indexes)}."
    }

    precondition {
      condition     = length(local.undeclared_insights_indexes) == 0
      error_message = "contributor_insights_indexes must name keys of global_secondary_indexes. Undeclared: ${join(", ", local.undeclared_insights_indexes)}."
    }

    precondition {
      condition     = length(var.replicas) == 0 || try(var.stream.view_type, null) == "NEW_AND_OLD_IMAGES"
      error_message = "replicas require stream = { view_type = \"NEW_AND_OLD_IMAGES\" }."
    }

    precondition {
      condition     = length(var.replicas) == 0 || !local.provisioned || var.autoscaling != null
      error_message = "replicas require billing_mode = \"PAY_PER_REQUEST\" or autoscaling on a PROVISIONED table, so every region can absorb replicated writes."
    }

    precondition {
      condition     = var.server_side_encryption.kms_key_arn == null || length(local.replicas_without_key) == 0
      error_message = "The table uses a customer managed key, so every replica must name its own regional kms_key_arn. Missing in: ${join(", ", local.replicas_without_key)}."
    }
  }
}

resource "aws_dynamodb_table" "autoscaled" {
  count = var.autoscaling == null ? 0 : 1

  # checkov:skip=CKV_AWS_119: Encryption is always enabled; the AWS owned key is the deliberate default and server_side_encryption.kms_key_arn selects a customer managed key.

  name                        = var.name
  billing_mode                = var.billing_mode
  hash_key                    = var.hash_key
  range_key                   = var.range_key
  read_capacity               = local.read_capacity
  write_capacity              = local.write_capacity
  table_class                 = var.table_class
  deletion_protection_enabled = var.deletion_protection_enabled
  stream_enabled              = var.stream != null
  stream_view_type            = var.stream == null ? null : var.stream.view_type

  dynamic "attribute" {
    for_each = var.attributes

    content {
      name = attribute.key
      type = attribute.value
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
      read_capacity      = local.gsi_capacities[global_secondary_index.key].read
      write_capacity     = local.gsi_capacities[global_secondary_index.key].write

      dynamic "on_demand_throughput" {
        for_each = global_secondary_index.value.on_demand_throughput == null ? [] : [global_secondary_index.value.on_demand_throughput]

        content {
          max_read_request_units  = on_demand_throughput.value.max_read_request_units
          max_write_request_units = on_demand_throughput.value.max_write_request_units
        }
      }
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_indexes

    content {
      name               = local_secondary_index.key
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.non_key_attributes
    }
  }

  dynamic "on_demand_throughput" {
    for_each = var.on_demand_throughput == null ? [] : [var.on_demand_throughput]

    content {
      max_read_request_units  = on_demand_throughput.value.max_read_request_units
      max_write_request_units = on_demand_throughput.value.max_write_request_units
    }
  }

  dynamic "replica" {
    for_each = var.replicas

    content {
      region_name                 = replica.key
      kms_key_arn                 = replica.value.kms_key_arn
      point_in_time_recovery      = replica.value.point_in_time_recovery == null ? var.point_in_time_recovery.enabled : replica.value.point_in_time_recovery
      propagate_tags              = replica.value.propagate_tags
      deletion_protection_enabled = replica.value.deletion_protection_enabled == null ? var.deletion_protection_enabled : replica.value.deletion_protection_enabled
      consistency_mode            = replica.value.consistency_mode
    }
  }

  point_in_time_recovery {
    enabled                 = var.point_in_time_recovery.enabled
    recovery_period_in_days = var.point_in_time_recovery.recovery_period_in_days
  }

  # Encryption at rest is always on. The AWS owned key is the deliberate
  # default; server_side_encryption.kms_key_arn selects a customer managed key.
  # See README, Security model.
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.server_side_encryption.kms_key_arn
  }

  dynamic "ttl" {
    for_each = var.ttl == null ? [] : [var.ttl]

    content {
      enabled        = ttl.value.enabled
      attribute_name = ttl.value.enabled ? ttl.value.attribute_name : null
    }
  }

  timeouts {
    create = try(var.timeouts.create, null)
    update = try(var.timeouts.update, null)
    delete = try(var.timeouts.delete, null)
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = length(local.undeclared_key_attributes) == 0
      error_message = "Every key attribute must be declared in attributes. Undeclared: ${join(", ", local.undeclared_key_attributes)}."
    }

    precondition {
      condition     = length(local.unused_attributes) == 0
      error_message = "DynamoDB rejects attribute definitions that no key uses. Remove from attributes or use in a key: ${join(", ", local.unused_attributes)}."
    }

    precondition {
      condition     = var.range_key == null ? true : var.hash_key != var.range_key
      error_message = "range_key must differ from hash_key."
    }

    precondition {
      condition     = length(local.duplicate_index_names) == 0
      error_message = "Global and local secondary index names must be unique across both maps. Duplicated: ${join(", ", local.duplicate_index_names)}."
    }

    precondition {
      condition     = length(var.local_secondary_indexes) == 0 || var.range_key != null
      error_message = "local_secondary_indexes require the table to have a range_key."
    }

    precondition {
      condition     = var.ttl == null ? true : !contains(local.key_attributes, var.ttl.attribute_name)
      error_message = "ttl.attribute_name must not be a key attribute of the table or of an index."
    }

    precondition {
      condition     = !local.provisioned || (local.read_capacity != null && local.write_capacity != null)
      error_message = "A PROVISIONED table needs read_capacity and write_capacity, or an autoscaling.table dimension for each."
    }

    precondition {
      condition     = !local.provisioned || length(local.gsis_without_capacity) == 0
      error_message = "Every GSI of a PROVISIONED table needs read_capacity and write_capacity, or an autoscaling.indexes dimension for each. Missing on: ${join(", ", local.gsis_without_capacity)}."
    }

    precondition {
      condition     = length(local.capacities_outside_bounds) == 0
      error_message = "An explicit capacity on an autoscaled dimension is its initial value and must lie within min_capacity and max_capacity. Outside bounds: ${join(", ", local.capacities_outside_bounds)}."
    }

    precondition {
      condition     = local.provisioned || (var.read_capacity == null && var.write_capacity == null && length(local.on_demand_gsis_with_capacity) == 0)
      error_message = "A PAY_PER_REQUEST table cannot set read_capacity or write_capacity on the table or on a GSI. Set billing_mode = \"PROVISIONED\" or remove the capacities."
    }

    precondition {
      condition     = local.provisioned || var.autoscaling == null
      error_message = "autoscaling applies to PROVISIONED tables only. On-demand tables scale on their own; use on_demand_throughput to cap them."
    }

    precondition {
      condition     = !local.provisioned || (var.on_demand_throughput == null && length(local.provisioned_gsis_with_on_demand) == 0)
      error_message = "on_demand_throughput on the table or a GSI requires billing_mode = \"PAY_PER_REQUEST\"."
    }

    precondition {
      condition     = length(local.undeclared_autoscaled_indexes) == 0
      error_message = "autoscaling.indexes must name keys of global_secondary_indexes. Undeclared: ${join(", ", local.undeclared_autoscaled_indexes)}."
    }

    precondition {
      condition     = length(local.undeclared_insights_indexes) == 0
      error_message = "contributor_insights_indexes must name keys of global_secondary_indexes. Undeclared: ${join(", ", local.undeclared_insights_indexes)}."
    }

    precondition {
      condition     = length(var.replicas) == 0 || try(var.stream.view_type, null) == "NEW_AND_OLD_IMAGES"
      error_message = "replicas require stream = { view_type = \"NEW_AND_OLD_IMAGES\" }."
    }

    precondition {
      condition     = length(var.replicas) == 0 || !local.provisioned || var.autoscaling != null
      error_message = "replicas require billing_mode = \"PAY_PER_REQUEST\" or autoscaling on a PROVISIONED table, so every region can absorb replicated writes."
    }

    precondition {
      condition     = var.server_side_encryption.kms_key_arn == null || length(local.replicas_without_key) == 0
      error_message = "The table uses a customer managed key, so every replica must name its own regional kms_key_arn. Missing in: ${join(", ", local.replicas_without_key)}."
    }
    ignore_changes = [read_capacity, write_capacity, global_secondary_index]
  }
}
