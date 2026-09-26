variable "region" {
  description = "AWS region of every table."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every table name; the table key is appended (<prefix>-<key>)."
  type        = string
  default     = "platform"
}

variable "tables" {
  description = "Tables to create, keyed by a short name that becomes the suffix of the table name. attributes must declare exactly the attributes used by the keys and index keys."
  type = map(object({
    hash_key   = string
    range_key  = optional(string)
    attributes = map(string)
    global_secondary_indexes = optional(map(object({
      hash_key           = string
      range_key          = optional(string)
      projection_type    = string
      non_key_attributes = optional(set(string))
    })), {})
    ttl_attribute    = optional(string)
    stream_view_type = optional(string)
  }))
}

variable "tags" {
  description = "Tags applied to every table."
  type        = map(string)
  default     = {}
}
