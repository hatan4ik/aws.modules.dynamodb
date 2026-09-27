# Integration suite: a PROVISIONED table and its GSI under Application Auto
# Scaling, applied for real in the caller's own account. Proves that the
# autoscaled table variant, the scalable targets, and the target-tracking
# policies are accepted by the DynamoDB and Application Auto Scaling APIs.
# Capacities are the smallest that satisfy the bounds; everything is destroyed
# at the end of the file, so deletion protection is off.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/provisioned-autoscaled.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "dynamodb-it"
  }
}

run "provisioned_autoscaled" {
  variables {
    name       = run.setup.name
    hash_key   = "pk"
    range_key  = "sk"
    attributes = { pk = "S", sk = "S", status = "S" }
    tags       = run.setup.tags

    billing_mode = "PROVISIONED"

    # Explicit initial table capacities within the bounds; the index starts at
    # its dimension minimums.
    read_capacity  = 2
    write_capacity = 2

    global_secondary_indexes = {
      by_status = { hash_key = "status", projection_type = "KEYS_ONLY" }
    }

    autoscaling = {
      table = {
        read  = { min_capacity = 1, max_capacity = 4 }
        write = { min_capacity = 1, max_capacity = 4, target_utilization = 60 }
      }
      indexes = {
        by_status = {
          read  = { min_capacity = 1, max_capacity = 4 }
          write = { min_capacity = 1, max_capacity = 4 }
        }
      }
    }

    deletion_protection_enabled = false
  }

  expect_failures = [check.deletion_protection_disabled]

  assert {
    condition     = length(aws_dynamodb_table.this) == 0 && length(aws_dynamodb_table.autoscaled) == 1 && aws_dynamodb_table.autoscaled[0].billing_mode == "PROVISIONED"
    error_message = "Only the autoscaled table variant may exist for a provisioned table with autoscaling."
  }

  assert {
    condition     = aws_dynamodb_table.autoscaled[0].read_capacity == 2 && aws_dynamodb_table.autoscaled[0].write_capacity == 2
    error_message = "Explicit initial capacities must have been applied."
  }

  assert {
    condition     = one([for index in aws_dynamodb_table.autoscaled[0].global_secondary_index : index.read_capacity if index.name == "by_status"]) == 1 && one([for index in aws_dynamodb_table.autoscaled[0].global_secondary_index : index.write_capacity if index.name == "by_status"]) == 1
    error_message = "The GSI must start at its autoscaling minimums."
  }

  assert {
    condition     = output.autoscaling_target_resource_ids == { table_read = "table/${run.setup.name}", table_write = "table/${run.setup.name}", index_by_status_read = "table/${run.setup.name}/index/by_status", index_by_status_write = "table/${run.setup.name}/index/by_status" }
    error_message = "Four scalable targets must have been registered against the real table and index."
  }

  assert {
    condition     = length(output.autoscaling_policy_arns) == 4 && alltrue([for arn in values(output.autoscaling_policy_arns) : startswith(arn, "arn:")])
    error_message = "Four target-tracking policies must have been created."
  }

  assert {
    condition     = output.name == run.setup.name && startswith(output.arn, "arn:") && output.billing_mode == "PROVISIONED"
    error_message = "Outputs must resolve from the autoscaled variant."
  }
}
