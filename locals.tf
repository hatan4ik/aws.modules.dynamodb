locals {
  provisioned = var.billing_mode == "PROVISIONED"

  # Every attribute referenced by a key, against every attribute declared.
  # DynamoDB rejects both an undeclared key attribute and a declared attribute
  # that no key uses, so the table preconditions compare the two sets.
  key_attributes = toset(concat(
    compact([var.hash_key, var.range_key]),
    flatten([for index in values(var.global_secondary_indexes) : compact([index.hash_key, index.range_key])]),
    [for index in values(var.local_secondary_indexes) : index.range_key],
  ))
  declared_attributes       = toset(keys(var.attributes))
  undeclared_key_attributes = sort(setsubtract(local.key_attributes, local.declared_attributes))
  unused_attributes         = sort(setsubtract(local.declared_attributes, local.key_attributes))

  index_names           = concat(keys(var.global_secondary_indexes), keys(var.local_secondary_indexes))
  duplicate_index_names = sort(distinct([for name in local.index_names : name if length([for other in local.index_names : other if other == name]) > 1]))

  # Autoscaling dimensions, resolved once so the table and its preconditions
  # agree on which capacities the scaler owns.
  autoscaled_table_read  = try(var.autoscaling.table.read, null)
  autoscaled_table_write = try(var.autoscaling.table.write, null)
  autoscaled_indexes     = try(var.autoscaling.indexes, {})

  # Initial capacities of a PROVISIONED table: the explicit value, otherwise the
  # autoscaling minimum. Null on on-demand tables; null on a provisioned table
  # only when neither is declared, which a precondition rejects.
  read_capacity  = !local.provisioned ? null : (var.read_capacity != null ? var.read_capacity : try(local.autoscaled_table_read.min_capacity, null))
  write_capacity = !local.provisioned ? null : (var.write_capacity != null ? var.write_capacity : try(local.autoscaled_table_write.min_capacity, null))

  gsi_capacities = {
    for name, index in var.global_secondary_indexes : name => {
      read  = !local.provisioned ? null : (index.read_capacity != null ? index.read_capacity : try(local.autoscaled_indexes[name].read.min_capacity, null))
      write = !local.provisioned ? null : (index.write_capacity != null ? index.write_capacity : try(local.autoscaled_indexes[name].write.min_capacity, null))
    }
  }
  gsis_without_capacity = sort([for name, capacity in local.gsi_capacities : name if capacity.read == null || capacity.write == null])

  # An explicit capacity on an autoscaled dimension is its initial value and
  # must lie within the dimension's bounds.
  capacities_outside_bounds = sort(concat(
    var.read_capacity == null || local.autoscaled_table_read == null ? [] : (var.read_capacity >= local.autoscaled_table_read.min_capacity && var.read_capacity <= local.autoscaled_table_read.max_capacity ? [] : ["read_capacity"]),
    var.write_capacity == null || local.autoscaled_table_write == null ? [] : (var.write_capacity >= local.autoscaled_table_write.min_capacity && var.write_capacity <= local.autoscaled_table_write.max_capacity ? [] : ["write_capacity"]),
    flatten([for name, index in var.global_secondary_indexes : concat(
      index.read_capacity == null || try(local.autoscaled_indexes[name].read, null) == null ? [] : (index.read_capacity >= local.autoscaled_indexes[name].read.min_capacity && index.read_capacity <= local.autoscaled_indexes[name].read.max_capacity ? [] : ["${name}.read_capacity"]),
      index.write_capacity == null || try(local.autoscaled_indexes[name].write, null) == null ? [] : (index.write_capacity >= local.autoscaled_indexes[name].write.min_capacity && index.write_capacity <= local.autoscaled_indexes[name].write.max_capacity ? [] : ["${name}.write_capacity"]),
    )]),
  ))

  undeclared_autoscaled_indexes   = sort(setsubtract(toset(keys(local.autoscaled_indexes)), toset(keys(var.global_secondary_indexes))))
  undeclared_insights_indexes     = sort(setsubtract(var.contributor_insights_indexes, toset(keys(var.global_secondary_indexes))))
  replicas_without_key            = sort([for region, replica in var.replicas : region if replica.kms_key_arn == null])
  on_demand_gsis_with_capacity    = sort([for name, index in var.global_secondary_indexes : name if index.read_capacity != null || index.write_capacity != null])
  provisioned_gsis_with_on_demand = sort([for name, index in var.global_secondary_indexes : name if index.on_demand_throughput != null])

  # Exactly one table variant exists; see table.tf.
  table = var.autoscaling == null ? aws_dynamodb_table.this[0] : aws_dynamodb_table.autoscaled[0]

  # Resource-based policy: statements sorted by Sid, principals, actions,
  # resources, and condition values sorted, no null or empty keys, so the
  # rendered JSON only changes when a statement actually changes.
  resource_policy_statements = [
    for sid in sort(keys(var.resource_policy_statements)) : merge(
      {
        Sid       = sid
        Effect    = var.resource_policy_statements[sid].effect
        Principal = { for type in sort(keys(var.resource_policy_statements[sid].principals)) : type => sort(tolist(var.resource_policy_statements[sid].principals[type])) }
        Action    = sort(tolist(var.resource_policy_statements[sid].actions))
        Resource  = var.resource_policy_statements[sid].resources == null ? [local.table.arn, "${local.table.arn}/index/*"] : sort(tolist(var.resource_policy_statements[sid].resources))
      },
      length(var.resource_policy_statements[sid].conditions) == 0 ? {} : {
        Condition = {
          for test in sort(distinct([for condition in var.resource_policy_statements[sid].conditions : condition.test])) : test => {
            for condition in var.resource_policy_statements[sid].conditions : condition.variable => sort(tolist(condition.values)) if condition.test == test
          }
        }
      },
    )
  ]
  resource_policy = length(var.resource_policy_statements) == 0 ? null : jsonencode({
    Version   = "2012-10-17"
    Statement = local.resource_policy_statements
  })
}
