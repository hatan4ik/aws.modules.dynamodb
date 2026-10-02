# Terraform cannot make lifecycle.ignore_changes conditional, so two table
# resources exist and exactly one is created. Keep their bodies identical;
# only count and the ignore_changes list differ. scripts/check-resource-variants.sh
# enforces this in make check and pre-commit.
#
# The autoscaled variant ignores read_capacity, write_capacity, and
# global_secondary_index: Application Auto Scaling owns the capacities after
# creation, and global_secondary_index is a set, so its capacities cannot be
# ignored individually. It also ignores replica: an autoscaled table renders no
# inline replicas (local.inline_replicas is empty) because DynamoDB only accepts
# a replica of a PROVISIONED table once write autoscaling is registered, which
# needs the table to exist first. Its replicas are aws_dynamodb_table_replica.this
# at the end of this file, created after modules/autoscaling.
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
    for_each = local.inline_replicas

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
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  tags = merge({ Name = var.name }, var.tags)

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
      condition     = length(local.replicated_writes_not_autoscaled) == 0
      error_message = "replicas of a PROVISIONED table require write autoscaling on the table and on every GSI; DynamoDB rejects the replica otherwise (\"write capacity should either be Pay-Per-Request or AutoScaled\"). Add an autoscaling write dimension for: ${join(", ", local.replicated_writes_not_autoscaled)}, or use billing_mode = \"PAY_PER_REQUEST\"."
    }

    precondition {
      condition     = length(local.replicas_with_mismatched_encryption) == 0
      error_message = var.server_side_encryption.kms_key_arn == null ? "The table uses the AWS owned key, so no replica may name a kms_key_arn; the encryption posture must be the same in every region. Set server_side_encryption.kms_key_arn on the table or remove the key from: ${join(", ", local.replicas_with_mismatched_encryption)}." : "The table uses a customer managed key, so every replica must name its own regional kms_key_arn. Missing in: ${join(", ", local.replicas_with_mismatched_encryption)}."
    }

    precondition {
      condition     = var.autoscaling == null || length(local.strongly_consistent_replicas) == 0
      error_message = "consistency_mode = \"STRONG\" is not supported on an autoscaled PROVISIONED table: its replicas are created one at a time after autoscaling is registered, and multi-Region strong consistency needs every replica in one request. Use PAY_PER_REQUEST for: ${join(", ", local.strongly_consistent_replicas)}."
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
    for_each = local.inline_replicas

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
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  tags = merge({ Name = var.name }, var.tags)

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
      condition     = length(local.replicated_writes_not_autoscaled) == 0
      error_message = "replicas of a PROVISIONED table require write autoscaling on the table and on every GSI; DynamoDB rejects the replica otherwise (\"write capacity should either be Pay-Per-Request or AutoScaled\"). Add an autoscaling write dimension for: ${join(", ", local.replicated_writes_not_autoscaled)}, or use billing_mode = \"PAY_PER_REQUEST\"."
    }

    precondition {
      condition     = length(local.replicas_with_mismatched_encryption) == 0
      error_message = var.server_side_encryption.kms_key_arn == null ? "The table uses the AWS owned key, so no replica may name a kms_key_arn; the encryption posture must be the same in every region. Set server_side_encryption.kms_key_arn on the table or remove the key from: ${join(", ", local.replicas_with_mismatched_encryption)}." : "The table uses a customer managed key, so every replica must name its own regional kms_key_arn. Missing in: ${join(", ", local.replicas_with_mismatched_encryption)}."
    }

    precondition {
      condition     = var.autoscaling == null || length(local.strongly_consistent_replicas) == 0
      error_message = "consistency_mode = \"STRONG\" is not supported on an autoscaled PROVISIONED table: its replicas are created one at a time after autoscaling is registered, and multi-Region strong consistency needs every replica in one request. Use PAY_PER_REQUEST for: ${join(", ", local.strongly_consistent_replicas)}."
    }
    ignore_changes = [read_capacity, write_capacity, global_secondary_index, replica]
  }
}

# Replicas of an autoscaled table. aws_dynamodb_table's own create adds inline
# replicas before any other resource can run, so on a PROVISIONED table the
# replica request would reach DynamoDB before modules/autoscaling registers the
# write scalable targets and fail with "write capacity should either be
# Pay-Per-Request or AutoScaled", on every apply. Separate replica resources
# that depend on the autoscaling module put the calls in the order DynamoDB
# requires: table, scalable targets and policies, then replicas. On-demand
# tables keep their replicas inline (local.separate_replicas is empty).
resource "aws_dynamodb_table_replica" "this" {
  for_each = local.separate_replicas

  region                      = each.key
  global_table_arn            = local.table.arn
  kms_key_arn                 = each.value.kms_key_arn
  point_in_time_recovery      = each.value.point_in_time_recovery == null ? var.point_in_time_recovery.enabled : each.value.point_in_time_recovery
  deletion_protection_enabled = each.value.deletion_protection_enabled == null ? var.deletion_protection_enabled : each.value.deletion_protection_enabled
  tags                        = each.value.propagate_tags ? merge({ Name = var.name }, var.tags) : null

  depends_on = [module.autoscaling]
}
