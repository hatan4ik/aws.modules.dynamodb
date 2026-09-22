variable "name" {
  description = "DynamoDB table name."
  type        = string
}

variable "hash_key" {
  description = "Partition-key attribute name."
  type        = string
}

variable "range_key" {
  description = "Optional sort-key attribute name."
  type        = string
  default     = null
  nullable    = true
}

variable "attributes" {
  description = "Attributes required by the primary key and any secondary indexes."
  type = map(object({
    type = string
  }))
}

variable "billing_mode" {
  description = "DynamoDB billing mode."
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode must be PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "read_capacity" {
  description = "Read capacity when billing_mode is PROVISIONED."
  type        = number
  default     = null
  nullable    = true
}

variable "write_capacity" {
  description = "Write capacity when billing_mode is PROVISIONED."
  type        = number
  default     = null
  nullable    = true
}

variable "global_secondary_indexes" {
  description = "Global secondary indexes keyed by a stable logical name."
  type = map(object({
    hash_key           = string
    range_key          = optional(string)
    projection_type    = string
    non_key_attributes = optional(set(string))
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  default = {}
}

variable "ttl_attribute_name" {
  description = "Optional TTL attribute name."
  type        = string
  default     = null
  nullable    = true
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for server-side encryption."
  type        = string
  default     = null
  nullable    = true
}

variable "point_in_time_recovery_enabled" {
  description = "Whether point-in-time recovery is enabled."
  type        = bool
  default     = true
}

variable "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the table."
  type        = map(string)
  default     = {}
}
