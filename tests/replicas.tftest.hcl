mock_provider "aws" {}

variables {
  name       = "orders"
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S" }
  stream     = { view_type = "NEW_AND_OLD_IMAGES" }
}

run "renders_replicas_inheriting_table_protection" {
  command = plan

  variables {
    replicas = {
      "eu-west-1"      = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/22222222-2222-2222-2222-222222222222" }
      "ap-southeast-2" = { point_in_time_recovery = false, deletion_protection_enabled = false, propagate_tags = false, consistency_mode = "EVENTUAL" }
    }
  }

  assert {
    condition     = length([for replica in aws_dynamodb_table.this[0].replica : replica.region_name]) == 2 && aws_dynamodb_table.this[0].stream_enabled == true && aws_dynamodb_table.this[0].stream_view_type == "NEW_AND_OLD_IMAGES"
    error_message = "Every replica region must render on a table streaming new and old images."
  }

  assert {
    condition     = one([for replica in aws_dynamodb_table.this[0].replica : replica.point_in_time_recovery if replica.region_name == "eu-west-1"]) == true && one([for replica in aws_dynamodb_table.this[0].replica : replica.deletion_protection_enabled if replica.region_name == "eu-west-1"]) == true && one([for replica in aws_dynamodb_table.this[0].replica : replica.propagate_tags if replica.region_name == "eu-west-1"]) == true
    error_message = "A replica must inherit the table's recovery and deletion protection and propagate tags by default."
  }

  assert {
    condition     = one([for replica in aws_dynamodb_table.this[0].replica : replica.kms_key_arn if replica.region_name == "eu-west-1"]) == "arn:aws:kms:eu-west-1:123456789012:key/22222222-2222-2222-2222-222222222222"
    error_message = "A replica's regional key must pass through."
  }

  assert {
    condition     = one([for replica in aws_dynamodb_table.this[0].replica : replica.point_in_time_recovery if replica.region_name == "ap-southeast-2"]) == false && one([for replica in aws_dynamodb_table.this[0].replica : replica.deletion_protection_enabled if replica.region_name == "ap-southeast-2"]) == false && one([for replica in aws_dynamodb_table.this[0].replica : replica.propagate_tags if replica.region_name == "ap-southeast-2"]) == false && one([for replica in aws_dynamodb_table.this[0].replica : replica.consistency_mode if replica.region_name == "ap-southeast-2"]) == "EVENTUAL"
    error_message = "Per-region overrides must win over the inherited settings."
  }

  assert {
    condition     = length(output.replica_arns) == 2 && contains(keys(output.replica_arns), "eu-west-1") && contains(keys(output.replica_arns), "ap-southeast-2")
    error_message = "Replica ARNs must be exposed keyed by region."
  }
}

run "allows_replicas_on_an_autoscaled_provisioned_table" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
    autoscaling  = { table = { read = { min_capacity = 5, max_capacity = 50 }, write = { min_capacity = 5, max_capacity = 50 } } }
    replicas     = { "eu-west-1" = {} }
  }

  assert {
    condition     = length(aws_dynamodb_table.autoscaled) == 1 && length([for replica in aws_dynamodb_table.autoscaled[0].replica : replica.region_name]) == 1 && length(output.replica_arns) == 1
    error_message = "A provisioned table with autoscaling may have replicas."
  }
}
