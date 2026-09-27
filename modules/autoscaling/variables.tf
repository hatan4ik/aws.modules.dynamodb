variable "table_name" {
  description = "Name of the PROVISIONED DynamoDB table to scale. Also prefixes policy names."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,255}$", var.table_name))
    error_message = "table_name must be 3-255 characters of letters, digits, underscores, hyphens, or dots."
  }
}

variable "table" {
  description = "Table-level dimensions to scale. Each of read and write is null (not scaled) or an object with min_capacity, max_capacity, target_utilization (percent, default 70), scale_in_cooldown (seconds, default 300), and scale_out_cooldown (seconds, default 60)."
  type = object({
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
  })
  default = null

  validation {
    condition = var.table == null ? true : alltrue([for dimension in [var.table.read, var.table.write] : dimension == null ? true : (
      dimension.min_capacity >= 1 && dimension.max_capacity >= dimension.min_capacity &&
      dimension.target_utilization >= 20 && dimension.target_utilization <= 90 &&
      dimension.scale_in_cooldown >= 0 && dimension.scale_out_cooldown >= 0
    )])
    error_message = "Each table dimension needs 1 <= min_capacity <= max_capacity, target_utilization between 20 and 90, and non-negative cooldowns."
  }
}

variable "indexes" {
  description = "Global secondary index dimensions to scale, keyed by index name. Each value has the same read and write shape as table; at least one of the two must be set."
  type = map(object({
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
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.indexes) : can(regex("^[a-zA-Z0-9_.-]{3,255}$", name))])
    error_message = "Index names must be 3-255 characters of letters, digits, underscores, hyphens, or dots."
  }

  validation {
    condition     = alltrue([for index in values(var.indexes) : index.read != null || index.write != null])
    error_message = "Each index must scale at least one of read or write."
  }

  validation {
    condition = alltrue(flatten([for index in values(var.indexes) : [for dimension in [index.read, index.write] : dimension == null ? true : (
      dimension.min_capacity >= 1 && dimension.max_capacity >= dimension.min_capacity &&
      dimension.target_utilization >= 20 && dimension.target_utilization <= 90 &&
      dimension.scale_in_cooldown >= 0 && dimension.scale_out_cooldown >= 0
    )]]))
    error_message = "Each index dimension needs 1 <= min_capacity <= max_capacity, target_utilization between 20 and 90, and non-negative cooldowns."
  }
}

variable "tags" {
  description = "Tags applied to every scalable target."
  type        = map(string)
  default     = {}
  nullable    = false
}
