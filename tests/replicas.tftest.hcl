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

  # Symmetric encryption posture: the table and every replica use customer
  # managed keys. A replica key on a table that uses the AWS owned key is
  # rejected (rejects_a_replica_key_when_the_table_uses_the_aws_owned_key).
  variables {
    server_side_encryption = { kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111" }
    replicas = {
      "eu-west-1"      = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/22222222-2222-2222-2222-222222222222" }
      "ap-southeast-2" = { kms_key_arn = "arn:aws:kms:ap-southeast-2:123456789012:key/33333333-3333-3333-3333-333333333333", point_in_time_recovery = false, deletion_protection_enabled = false, propagate_tags = false, consistency_mode = "EVENTUAL" }
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

run "renders_replicas_on_the_aws_owned_key" {
  command = plan

  variables {
    replicas = { "eu-west-1" = {}, "ap-southeast-2" = {} }
  }

  assert {
    condition     = length([for replica in aws_dynamodb_table.this[0].replica : replica.region_name]) == 2
    error_message = "A table on the AWS owned key may have replicas that name no key."
  }
}

run "rejects_a_replica_key_when_the_table_uses_the_aws_owned_key" {
  command = plan

  # Previously accepted: the table on the AWS owned key with one replica on a
  # customer managed key gave a different encryption posture per region.
  variables {
    replicas = {
      "eu-west-1"      = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/22222222-2222-2222-2222-222222222222" }
      "ap-southeast-2" = {}
    }
  }

  expect_failures = [aws_dynamodb_table.this]
}

# Provisioned global tables. DynamoDB accepts a replica of a PROVISIONED table
# only when write capacity is autoscaled on the table and on every GSI, and only
# once those scalable targets are registered. The module therefore requires the
# write dimensions at plan time and creates the replicas of an autoscaled table
# as aws_dynamodb_table_replica resources that depend on module.autoscaling.

run "creates_replicas_of_an_autoscaled_table_after_autoscaling" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
    attributes   = { pk = "S", sk = "S", status = "S" }
    tags         = { Owner = "platform" }
    global_secondary_indexes = {
      by_status = { hash_key = "status", projection_type = "KEYS_ONLY" }
    }
    autoscaling = {
      table   = { read = { min_capacity = 5, max_capacity = 50 }, write = { min_capacity = 5, max_capacity = 50 } }
      indexes = { by_status = { read = { min_capacity = 1, max_capacity = 10 }, write = { min_capacity = 1, max_capacity = 10 } } }
    }
    replicas = {
      "eu-west-1"      = {}
      "ap-southeast-2" = { point_in_time_recovery = false, deletion_protection_enabled = false, propagate_tags = false }
    }
  }

  assert {
    condition     = length(aws_dynamodb_table.autoscaled) == 1 && length([for replica in aws_dynamodb_table.autoscaled[0].replica : replica.region_name]) == 0
    error_message = "An autoscaled table must not create its replicas inline: that request would reach DynamoDB before write autoscaling is registered."
  }

  assert {
    condition     = toset(keys(aws_dynamodb_table_replica.this)) == toset(["eu-west-1", "ap-southeast-2"]) && aws_dynamodb_table_replica.this["eu-west-1"].region == "eu-west-1" && aws_dynamodb_table_replica.this["ap-southeast-2"].region == "ap-southeast-2"
    error_message = "Each replica of an autoscaled table must be a separate replica resource in its own region."
  }

  assert {
    condition     = aws_dynamodb_table_replica.this["eu-west-1"].point_in_time_recovery == true && aws_dynamodb_table_replica.this["eu-west-1"].deletion_protection_enabled == true && aws_dynamodb_table_replica.this["eu-west-1"].tags == tomap({ Name = "orders", Owner = "platform" })
    error_message = "A separate replica must inherit the table's recovery and deletion protection and carry the table's tags by default."
  }

  assert {
    condition     = aws_dynamodb_table_replica.this["ap-southeast-2"].point_in_time_recovery == false && aws_dynamodb_table_replica.this["ap-southeast-2"].deletion_protection_enabled == false && aws_dynamodb_table_replica.this["ap-southeast-2"].tags == null
    error_message = "Per-region overrides must win on a separate replica, and propagate_tags = false must leave its tags unmanaged."
  }

  assert {
    condition     = length(output.replica_arns) == 2 && contains(keys(output.replica_arns), "eu-west-1") && contains(keys(output.replica_arns), "ap-southeast-2")
    error_message = "Replica ARNs must be exposed keyed by region whichever variant exists."
  }

  assert {
    condition     = length(output.autoscaling_target_resource_ids) == 4 && contains(keys(output.autoscaling_target_resource_ids), "table_write") && contains(keys(output.autoscaling_target_resource_ids), "index_by_status_write")
    error_message = "Write autoscaling must be registered for the table and the index."
  }
}

run "rejects_replicas_of_a_provisioned_table_without_table_write_autoscaling" {
  command = plan

  # Passed plan before 1.1.0 and failed at apply with "write capacity should
  # either be Pay-Per-Request or AutoScaled".
  variables {
    billing_mode   = "PROVISIONED"
    write_capacity = 5
    autoscaling    = { table = { read = { min_capacity = 5, max_capacity = 50 } } }
    replicas       = { "eu-west-1" = {} }
  }

  expect_failures = [aws_dynamodb_table.autoscaled]
}

run "rejects_replicas_of_a_provisioned_table_without_index_write_autoscaling" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
    attributes   = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = {
      by_status = { hash_key = "status", projection_type = "KEYS_ONLY", write_capacity = 5 }
    }
    autoscaling = {
      table   = { read = { min_capacity = 5, max_capacity = 50 }, write = { min_capacity = 5, max_capacity = 50 } }
      indexes = { by_status = { read = { min_capacity = 1, max_capacity = 10 } } }
    }
    replicas = { "eu-west-1" = {} }
  }

  expect_failures = [aws_dynamodb_table.autoscaled]
}

run "rejects_strong_consistency_on_an_autoscaled_table" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
    autoscaling  = { table = { write = { min_capacity = 5, max_capacity = 50 }, read = { min_capacity = 5, max_capacity = 50 } } }
    replicas     = { "eu-west-1" = { consistency_mode = "STRONG" }, "eu-west-2" = { consistency_mode = "STRONG" } }
  }

  expect_failures = [aws_dynamodb_table.autoscaled]
}
