variable "region" {
  description = "AWS region of the table."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Table name; also the Name tag."
  type        = string
  default     = "orders"
}

variable "kms_key_arn" {
  description = "Customer managed KMS key that encrypts the table. Its key policy must allow the DynamoDB service to use it on behalf of the account."
  type        = string
}

variable "kinesis_stream_arn" {
  description = "Kinesis Data Stream that receives item-level changes from the table."
  type        = string
}

variable "analytics_role_arn" {
  description = "IAM role granted read-only access to the table and its indexes through the resource-based policy."
  type        = string
}

variable "organization_id" {
  description = "AWS Organizations ID (o-...) outside of which every principal is denied by the resource-based policy."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must be an AWS Organizations ID such as o-abcdef1234."
  }
}

variable "tags" {
  description = "Tags applied to the table and propagated to replicas and autoscaling targets."
  type        = map(string)
  default = {
    Environment = "production"
    Team        = "orders"
  }
}
