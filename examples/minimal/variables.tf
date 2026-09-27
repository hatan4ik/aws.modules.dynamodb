variable "region" {
  description = "AWS region of the table."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Table name."
  type        = string
  default     = "orders"
}

variable "tags" {
  description = "Tags applied to the table."
  type        = map(string)
  default     = {}
}
