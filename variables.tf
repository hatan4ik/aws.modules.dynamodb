# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "name" {
  description = "Table name: 3-255 characters of letters, digits, underscores, hyphens, or dots. Also the Name tag and the prefix of autoscaling policy names."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.name))
    error_message = "name must be 3-255 characters of letters, digits, underscores, hyphens, or dots."
  }
}

variable "tags" {
  description = "Tags applied to the table, propagated to replicas by default, and applied to autoscaling targets. The module adds a Name tag and never overrides caller tags."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ---------------------------------------------------------------------------
# Keys and attributes
# ---------------------------------------------------------------------------

variable "hash_key" {
  description = "Partition key attribute name. Must be declared in attributes."
  type        = string
  nullable    = false
}

variable "range_key" {
  description = "Sort key attribute name, or null for a partition-key-only table. Must be declared in attributes and differ from hash_key."
  type        = string
  default     = null
}

variable "attributes" {
  description = "Attribute definitions keyed by attribute name with the DynamoDB type S, N, or B as the value. Declare exactly the attributes used by the primary key and by index keys: DynamoDB rejects unused definitions and undeclared key attributes, and the module enforces both at plan time."
  type        = map(string)
  nullable    = false

  validation {
    condition     = length(var.attributes) > 0
    error_message = "attributes must declare at least the hash_key attribute."
  }

  validation {
    condition     = alltrue([for name, type in var.attributes : contains(["S", "N", "B"], type) && length(name) >= 1 && length(name) <= 255])
    error_message = "Every attribute name must be 1-255 characters and its type S, N, or B."
  }
}

# ---------------------------------------------------------------------------
# Throughput
# ---------------------------------------------------------------------------

variable "billing_mode" {
  description = "PAY_PER_REQUEST (on-demand) or PROVISIONED. Provisioned tables need read_capacity and write_capacity on the table and every GSI, or an autoscaling dimension covering each."
  type        = string
  default     = "PAY_PER_REQUEST"
  nullable    = false

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  description = "Provisioned read capacity units of the table. Required with PROVISIONED unless autoscaling.table.read is set, in which case it is the initial value and must lie within the bounds; forbidden with PAY_PER_REQUEST."
  type        = number
  default     = null

  validation {
    condition     = var.read_capacity == null ? true : var.read_capacity >= 1
    error_message = "read_capacity must be at least 1."
  }
}

variable "write_capacity" {
  description = "Provisioned write capacity units of the table. Required with PROVISIONED unless autoscaling.table.write is set, in which case it is the initial value and must lie within the bounds; forbidden with PAY_PER_REQUEST."
  type        = number
  default     = null

  validation {
    condition     = var.write_capacity == null ? true : var.write_capacity >= 1
    error_message = "write_capacity must be at least 1."
  }
}

variable "on_demand_throughput" {
  description = "Maximum read and write request units per second of an on-demand table. Each limit is at least 1, or -1 to remove a limit set earlier. Only valid with PAY_PER_REQUEST."
  type = object({
    max_read_request_units  = optional(number)
    max_write_request_units = optional(number)
  })
  default = null

  validation {
    condition = var.on_demand_throughput == null ? true : (
      (var.on_demand_throughput.max_read_request_units != null || var.on_demand_throughput.max_write_request_units != null) &&
      alltrue([for limit in [var.on_demand_throughput.max_read_request_units, var.on_demand_throughput.max_write_request_units] : limit == null ? true : (limit >= 1 || limit == -1)])
    )
    error_message = "on_demand_throughput must set at least one limit, and each limit must be at least 1 or exactly -1."
  }
}

variable "table_class" {
  description = "Storage class of the table: STANDARD or STANDARD_INFREQUENT_ACCESS."
  type        = string
  default     = "STANDARD"
  nullable    = false

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "table_class must be STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

variable "autoscaling" {
  description = "Application Auto Scaling for a PROVISIONED table. Null disables it. table.read, table.write, and each indexes.<gsi>.read or .write is a dimension with min_capacity, max_capacity, target_utilization (percent, default 70), scale_in_cooldown (default 300), and scale_out_cooldown (default 60). When set, the table ignores later capacity drift and unset capacities start at the dimension minimum. See modules/autoscaling."
  type = object({
    table = optional(object({
      read = optional(object({
        min_capacity       = number
        max_capacity       = number
        target_utilization = optional(number, 70)
        scale_in_cooldown  = optional(number, 300)
        scale_out_cooldown = optional(number, 60)
      }))
      write = optional(object({
        min_capacity       = number
        max_capacity       = number
        target_utilization = optional(number, 70)
        scale_in_cooldown  = optional(number, 300)
        scale_out_cooldown = optional(number, 60)
      }))
    }))
    indexes = optional(map(object({
      read = optional(object({
        min_capacity       = number
        max_capacity       = number
        target_utilization = optional(number, 70)
        scale_in_cooldown  = optional(number, 300)
        scale_out_cooldown = optional(number, 60)
      }))
      write = optional(object({
        min_capacity       = number
        max_capacity       = number
        target_utilization = optional(number, 70)
        scale_in_cooldown  = optional(number, 300)
        scale_out_cooldown = optional(number, 60)
      }))
    })), {})
  })
  default = null

  validation {
    condition = var.autoscaling == null ? true : (
      try(var.autoscaling.table.read, null) != null || try(var.autoscaling.table.write, null) != null ||
      anytrue([for index in values(var.autoscaling.indexes) : index.read != null || index.write != null])
    )
    error_message = "autoscaling must scale at least one dimension: table.read, table.write, or an indexes entry."
  }

  validation {
    condition     = var.autoscaling == null ? true : alltrue([for index in values(var.autoscaling.indexes) : index.read != null || index.write != null])
    error_message = "Every autoscaling.indexes entry must scale at least one of read or write."
  }

  validation {
    condition = var.autoscaling == null ? true : alltrue([
      for dimension in concat(
        [try(var.autoscaling.table.read, null), try(var.autoscaling.table.write, null)],
        flatten([for index in values(var.autoscaling.indexes) : [index.read, index.write]]),
        ) : dimension == null ? true : (
        dimension.min_capacity >= 1 && dimension.max_capacity >= dimension.min_capacity &&
        dimension.target_utilization >= 20 && dimension.target_utilization <= 90 &&
        dimension.scale_in_cooldown >= 0 && dimension.scale_out_cooldown >= 0
      )
    ])
    error_message = "Each autoscaling dimension needs 1 <= min_capacity <= max_capacity, target_utilization between 20 and 90, and non-negative cooldowns."
  }
}

# ---------------------------------------------------------------------------
# Indexes
# ---------------------------------------------------------------------------

variable "global_secondary_indexes" {
  description = "Global secondary indexes keyed by index name. projection_type is ALL, KEYS_ONLY, or INCLUDE (which requires non_key_attributes). Key attributes must be declared in attributes. read_capacity and write_capacity apply to PROVISIONED tables; on_demand_throughput to PAY_PER_REQUEST tables."
  type = map(object({
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(set(string))
    read_capacity      = optional(number)
    write_capacity     = optional(number)
    on_demand_throughput = optional(object({
      max_read_request_units  = optional(number)
      max_write_request_units = optional(number)
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.global_secondary_indexes) : can(regex("^[a-zA-Z0-9_.-]{3,255}$", name))])
    error_message = "Global secondary index names must be 3-255 characters of letters, digits, underscores, hyphens, or dots."
  }

  validation {
    condition = alltrue([for index in values(var.global_secondary_indexes) :
      contains(["ALL", "KEYS_ONLY", "INCLUDE"], index.projection_type) &&
      (index.projection_type == "INCLUDE" ? (index.non_key_attributes == null ? false : length(index.non_key_attributes) > 0) : (index.non_key_attributes == null ? true : length(index.non_key_attributes) == 0))
    ])
    error_message = "Each GSI projection_type must be ALL, KEYS_ONLY, or INCLUDE; INCLUDE requires non_key_attributes and the others forbid them."
  }

  validation {
    condition     = alltrue([for index in values(var.global_secondary_indexes) : index.range_key == null ? true : index.hash_key != index.range_key])
    error_message = "A GSI range_key must differ from its hash_key."
  }

  validation {
    condition     = alltrue([for index in values(var.global_secondary_indexes) : (index.read_capacity == null ? true : index.read_capacity >= 1) && (index.write_capacity == null ? true : index.write_capacity >= 1)])
    error_message = "GSI read_capacity and write_capacity must be at least 1 when set."
  }

  validation {
    condition = alltrue([for index in values(var.global_secondary_indexes) : index.on_demand_throughput == null ? true : (
      (index.on_demand_throughput.max_read_request_units != null || index.on_demand_throughput.max_write_request_units != null) &&
      alltrue([for limit in [index.on_demand_throughput.max_read_request_units, index.on_demand_throughput.max_write_request_units] : limit == null ? true : (limit >= 1 || limit == -1)])
    )])
    error_message = "A GSI on_demand_throughput must set at least one limit, and each limit must be at least 1 or exactly -1."
  }
}

variable "local_secondary_indexes" {
  description = "Local secondary indexes keyed by index name, at most five. Each shares the table hash_key and names its own range_key, which must be declared in attributes; the table needs a range_key. projection_type follows the GSI rules."
  type = map(object({
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(set(string))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(var.local_secondary_indexes) <= 5
    error_message = "A table may have at most five local secondary indexes."
  }

  validation {
    condition     = alltrue([for name in keys(var.local_secondary_indexes) : can(regex("^[a-zA-Z0-9_.-]{3,255}$", name))])
    error_message = "Local secondary index names must be 3-255 characters of letters, digits, underscores, hyphens, or dots."
  }

  validation {
    condition = alltrue([for index in values(var.local_secondary_indexes) :
      contains(["ALL", "KEYS_ONLY", "INCLUDE"], index.projection_type) &&
      (index.projection_type == "INCLUDE" ? (index.non_key_attributes == null ? false : length(index.non_key_attributes) > 0) : (index.non_key_attributes == null ? true : length(index.non_key_attributes) == 0))
    ])
    error_message = "Each LSI projection_type must be ALL, KEYS_ONLY, or INCLUDE; INCLUDE requires non_key_attributes and the others forbid them."
  }
}

# ---------------------------------------------------------------------------
# Data protection
# ---------------------------------------------------------------------------

variable "server_side_encryption" {
  description = "Encryption at rest is always enabled. kms_key_arn selects a customer managed KMS key; null uses the AWS owned key. Replicas of a table on a customer managed key must each name their own regional key."
  type = object({
    kms_key_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.server_side_encryption.kms_key_arn == null ? true : can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.server_side_encryption.kms_key_arn))
    error_message = "server_side_encryption.kms_key_arn must be a full KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "point_in_time_recovery" {
  description = "Point-in-time recovery, enabled by default. recovery_period_in_days (1-35) shortens the AWS default window and is only valid while enabled."
  type = object({
    enabled                 = optional(bool, true)
    recovery_period_in_days = optional(number)
  })
  # The default spells enabled = true out (the optional() default already
  # implies it) so static policy scanners can read the rendered value.
  default  = { enabled = true }
  nullable = false

  validation {
    condition     = var.point_in_time_recovery.recovery_period_in_days == null ? true : (var.point_in_time_recovery.enabled && var.point_in_time_recovery.recovery_period_in_days >= 1 && var.point_in_time_recovery.recovery_period_in_days <= 35)
    error_message = "point_in_time_recovery.recovery_period_in_days must be between 1 and 35 and requires enabled = true."
  }
}

variable "deletion_protection_enabled" {
  description = "Refuse to delete the table until this is set to false. On by default; the deletion_protection_disabled check warns while it is off."
  type        = bool
  default     = true
  nullable    = false
}

variable "ttl" {
  description = "Time to live on the named Number attribute holding an epoch-seconds expiry. Null leaves TTL unmanaged. enabled = false keeps the declaration while TTL is off; the attribute must not be a key attribute."
  type = object({
    attribute_name = string
    enabled        = optional(bool, true)
  })
  default = null

  validation {
    condition     = var.ttl == null ? true : (length(var.ttl.attribute_name) >= 1 && length(var.ttl.attribute_name) <= 255)
    error_message = "ttl.attribute_name must be 1-255 characters."
  }
}

# ---------------------------------------------------------------------------
# Integration
# ---------------------------------------------------------------------------

variable "stream" {
  description = "DynamoDB Streams. Null disables the stream. view_type is KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, or NEW_AND_OLD_IMAGES; replicas require NEW_AND_OLD_IMAGES."
  type = object({
    view_type = string
  })
  default = null

  validation {
    condition     = var.stream == null ? true : contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream.view_type)
    error_message = "stream.view_type must be KEYS_ONLY, NEW_IMAGE, OLD_IMAGE, or NEW_AND_OLD_IMAGES."
  }
}

variable "replicas" {
  description = "Global table replicas keyed by region name. kms_key_arn is the replica's regional customer managed key (required when the table uses one); point_in_time_recovery and deletion_protection_enabled default to the table's settings; propagate_tags defaults to true; consistency_mode is EVENTUAL or STRONG. Replicas need stream.view_type = NEW_AND_OLD_IMAGES and PAY_PER_REQUEST or autoscaling."
  type = map(object({
    kms_key_arn                 = optional(string)
    point_in_time_recovery      = optional(bool)
    propagate_tags              = optional(bool, true)
    deletion_protection_enabled = optional(bool)
    consistency_mode            = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for region in keys(var.replicas) : can(regex("^[a-z]{2,4}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "replicas keys must be AWS region names such as eu-west-1."
  }

  validation {
    condition     = alltrue([for replica in values(var.replicas) : replica.kms_key_arn == null ? true : can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", replica.kms_key_arn))])
    error_message = "Each replica kms_key_arn must be a full KMS key ARN in the replica's region, not an alias."
  }

  validation {
    condition     = alltrue([for replica in values(var.replicas) : replica.consistency_mode == null ? true : contains(["EVENTUAL", "STRONG"], replica.consistency_mode)])
    error_message = "Each replica consistency_mode must be EVENTUAL or STRONG."
  }
}

variable "kinesis_stream_arn" {
  description = "Kinesis Data Stream that receives item-level changes. Null creates no destination."
  type        = string
  default     = null

  validation {
    condition     = var.kinesis_stream_arn == null ? true : can(regex("^arn:[a-z-]+:kinesis:[a-z0-9-]+:[0-9]{12}:stream/.+$", var.kinesis_stream_arn))
    error_message = "kinesis_stream_arn must be a full Kinesis stream ARN (arn:<partition>:kinesis:<region>:<account>:stream/<name>)."
  }
}

variable "kinesis_approximate_creation_date_time_precision" {
  description = "Precision of the ApproximateCreationDateTime written to the Kinesis stream: MILLISECOND or MICROSECOND."
  type        = string
  default     = "MILLISECOND"
  nullable    = false

  validation {
    condition     = contains(["MILLISECOND", "MICROSECOND"], var.kinesis_approximate_creation_date_time_precision)
    error_message = "kinesis_approximate_creation_date_time_precision must be MILLISECOND or MICROSECOND."
  }
}

variable "resource_policy_statements" {
  description = "Resource-based policy statements keyed by alphanumeric Sid. principals maps a type (AWS, Service, Federated, CanonicalUser) to identifiers; a wildcard principal requires a condition. resources defaults to the table and every index. The rendered document is sorted and null-free; an empty map creates no policy."
  type = map(object({
    effect     = optional(string, "Allow")
    principals = map(set(string))
    actions    = set(string)
    resources  = optional(set(string))
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = set(string)
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for sid in keys(var.resource_policy_statements) : can(regex("^[A-Za-z0-9]{1,100}$", sid))])
    error_message = "resource_policy_statements keys are Sids: 1-100 letters and digits."
  }

  validation {
    condition     = alltrue([for statement in values(var.resource_policy_statements) : contains(["Allow", "Deny"], statement.effect)])
    error_message = "Each statement effect must be Allow or Deny."
  }

  validation {
    condition     = alltrue([for statement in values(var.resource_policy_statements) : length(statement.principals) > 0 && alltrue([for type, identifiers in statement.principals : contains(["AWS", "Service", "Federated", "CanonicalUser"], type) && length(identifiers) > 0])])
    error_message = "Each statement needs at least one principal; principal types are AWS, Service, Federated, or CanonicalUser, each with at least one identifier."
  }

  validation {
    condition     = alltrue([for statement in values(var.resource_policy_statements) : length(statement.actions) > 0 && (statement.resources == null ? true : length(statement.resources) > 0)])
    error_message = "Each statement needs at least one action, and resources, when set, at least one ARN."
  }

  validation {
    condition     = alltrue([for statement in values(var.resource_policy_statements) : anytrue([for identifiers in values(statement.principals) : contains(identifiers, "*")]) ? length(statement.conditions) > 0 : true])
    error_message = "A statement with a wildcard principal must carry at least one condition."
  }

  validation {
    condition = alltrue([for statement in values(var.resource_policy_statements) :
      length(distinct([for condition in statement.conditions : "${condition.test}:${condition.variable}"])) == length(statement.conditions) &&
      alltrue([for condition in statement.conditions : length(condition.values) > 0])
    ])
    error_message = "Each statement condition needs at least one value, and no two conditions may repeat the same test and variable."
  }
}

variable "contributor_insights_enabled" {
  description = "Enable CloudWatch Contributor Insights on the table."
  type        = bool
  default     = false
  nullable    = false
}

variable "contributor_insights_indexes" {
  description = "Global secondary index names to enable CloudWatch Contributor Insights on. Each must be a key of global_secondary_indexes."
  type        = set(string)
  default     = []
  nullable    = false
}

# ---------------------------------------------------------------------------
# Operations
# ---------------------------------------------------------------------------

variable "timeouts" {
  description = "Create, update, and delete timeouts for the table, as duration strings."
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default = null
}
