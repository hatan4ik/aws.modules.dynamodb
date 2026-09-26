variable "name_prefix" {
  description = "Prefix for the table name; a random suffix is appended so concurrent runs never collide."
  type        = string
  default     = "dynamodb-it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be 1-40 lowercase alphanumeric characters or hyphens."
  }
}

variable "tags" {
  description = "Tags applied to the table under test in addition to the identifying defaults."
  type        = map(string)
  default     = {}
}
