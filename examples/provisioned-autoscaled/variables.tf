variable "region" {
  description = "AWS region of the table."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Table name; also the prefix of the autoscaling policy names."
  type        = string
  default     = "orders-provisioned"
}

variable "tags" {
  description = "Tags applied to the table and to every scalable target."
  type        = map(string)
  default     = {}
}
