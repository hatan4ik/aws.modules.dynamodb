variable "region" {
  description = "Region of the primary table; the provider region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Table name, shared by every replica."
  type        = string
  default     = "orders-global"
}

variable "kms_key_arn" {
  description = "Customer managed KMS key in the primary region that encrypts the table."
  type        = string
}

variable "replica_kms_key_arns" {
  description = "Replica regions keyed by region name, each with the customer managed KMS key ARN in that region. Two regions make a global table; add or remove a key to add or remove a replica."
  type        = map(string)

  validation {
    condition     = length(var.replica_kms_key_arns) >= 1
    error_message = "Declare at least one replica region."
  }
}

variable "tags" {
  description = "Tags applied to the table and propagated to every replica."
  type        = map(string)
  default     = {}
}
