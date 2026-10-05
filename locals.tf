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

  undeclared_autoscaled_indexes = sort(setsubtract(toset(keys(local.autoscaled_indexes)), toset(keys(var.global_secondary_indexes))))
  undeclared_insights_indexes   = sort(setsubtract(var.contributor_insights_indexes, toset(keys(var.global_secondary_indexes))))

  # DynamoDB rejects a replica of a PROVISIONED table unless write capacity is
  # autoscaled on the table and on every GSI ("write capacity should either be
  # Pay-Per-Request or AutoScaled"). Read capacity may stay fixed.
  replicated_writes_not_autoscaled = !local.provisioned || length(var.replicas) == 0 ? [] : concat(
    local.autoscaled_table_write == null ? ["table"] : [],
    sort([for name in keys(var.global_secondary_indexes) : "index ${name}" if try(local.autoscaled_indexes[name].write, null) == null]),
  )

  # Replicas of an on-demand table are rendered inline on the table. Replicas
  # of an autoscaled (PROVISIONED) table are separate aws_dynamodb_table_replica
  # resources created after modules/autoscaling: DynamoDB only accepts them once
  # write autoscaling is registered, and the scalable targets can only be
  # registered once the table exists. Both table variants render
  # local.inline_replicas so their bodies stay identical.
  inline_replicas   = var.autoscaling == null ? var.replicas : {}
  separate_replicas = var.autoscaling == null ? {} : var.replicas

  # Encryption posture must be the same in every region: either the table and
  # every replica use customer managed keys, or none of them does.
  replicas_without_key                = sort([for region, replica in var.replicas : region if replica.kms_key_arn == null])
  replicas_with_key                   = sort([for region, replica in var.replicas : region if replica.kms_key_arn != null])
  replicas_with_mismatched_encryption = var.server_side_encryption.kms_key_arn == null ? local.replicas_with_key : local.replicas_without_key

  # Multi-Region strong consistency creates every replica in one UpdateTable
  # call, which separate replica resources cannot express.
  strongly_consistent_replicas = sort([for region, replica in var.replicas : region if replica.consistency_mode == "STRONG"])

  on_demand_gsis_with_capacity    = sort([for name, index in var.global_secondary_indexes : name if index.read_capacity != null || index.write_capacity != null])
  provisioned_gsis_with_on_demand = sort([for name, index in var.global_secondary_indexes : name if index.on_demand_throughput != null])

  # Exactly one table variant exists; see table.tf.
  table = var.autoscaling == null ? aws_dynamodb_table.this[0] : aws_dynamodb_table.autoscaled[0]

  # Resource-based policy: statements sorted by Sid, principals, actions,
  # resources, and condition values sorted, no null or empty keys, so the
  # rendered JSON only changes when a statement actually changes.
  #
  # The document is rendered once as a template whose default Resource list
  # names a placeholder token, then the token is replaced with the table ARN.
  # Table ARNs contain no character jsonencode escapes, so the result is
  # byte-identical to rendering the ARN directly, and the same template yields
  # a size estimate that is known at plan time, before the table exists.
  resource_policy_arn_token = "MODULE_TABLE_ARN_PLACEHOLDER"
  resource_policy_statements = [
    for sid in sort(keys(var.resource_policy_statements)) : merge(
      {
        Sid       = sid
        Effect    = var.resource_policy_statements[sid].effect
        Principal = { for type in sort(keys(var.resource_policy_statements[sid].principals)) : type => sort(tolist(var.resource_policy_statements[sid].principals[type])) }
        Action    = sort(tolist(var.resource_policy_statements[sid].actions))
        Resource  = var.resource_policy_statements[sid].resources == null ? [local.resource_policy_arn_token, "${local.resource_policy_arn_token}/index/*"] : sort(tolist(var.resource_policy_statements[sid].resources))
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
  resource_policy_template = length(var.resource_policy_statements) == 0 ? null : jsonencode({
    Version   = "2012-10-17"
    Statement = local.resource_policy_statements
  })
  # Only a document that uses the default Resource list depends on the table
  # ARN; one whose statements all name their resources stays known at plan.
  resource_policy = local.resource_policy_template == null ? null : (strcontains(local.resource_policy_template, local.resource_policy_arn_token) ? replace(local.resource_policy_template, local.resource_policy_arn_token, local.table.arn) : local.resource_policy_template)

  # DynamoDB caps a resource-based policy document at 20 KB and counts
  # whitespace (PutResourcePolicy; Developer Guide, "Resource-based policy
  # considerations"). jsonencode emits no whitespace. The estimate substitutes
  # the longest ARN prefix any partition and region can produce
  # (arn:aws-iso-b:dynamodb:ap-southeast-5:123456789012:table/, 57 characters)
  # followed by the table name, so it never under-counts the real document.
  resource_policy_max_length      = 20480
  resource_policy_arn_upper_bound = "${join("", [for i in range(57) : "x"])}${var.name}"
  resource_policy_length_estimate = local.resource_policy_template == null ? 0 : length(replace(local.resource_policy_template, local.resource_policy_arn_token, local.resource_policy_arn_upper_bound))
}
