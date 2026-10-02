# Integration suite: a PROVISIONED global table under Application Auto Scaling,
# applied for real in the caller's own account, in one apply.
#
# DynamoDB accepts a replica of a PROVISIONED table only once write capacity
# on the table and on every GSI is autoscaled. The scalable targets can only be
# registered after the table exists, so replicas declared inline on the table
# fail on the first apply with "write capacity should either be Pay-Per-Request
# or AutoScaled". This suite proves the module's ordering: table, then
# modules/autoscaling, then aws_dynamodb_table_replica.this, all in one
# `terraform apply`, with a GSI so the index write requirement is exercised too.
# Everything is destroyed at the end of the file (replica first), so deletion
# protection is off on the table and the replica.
#
# Needs: credentials, AWS_REGION, and a second region in TF_VAR_replica_region.
# Run: terraform init -backend=false -test-directory=tests/integration
#      TF_VAR_replica_region=<region> terraform test -test-directory=tests/integration -filter=tests/integration/global-provisioned-autoscaled.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "dynamodb-it"
  }

  assert {
    condition     = output.replica_region != null && output.replica_region != output.region
    error_message = "Set TF_VAR_replica_region to a region other than AWS_REGION; this suite creates a replica there."
  }
}

run "global_provisioned_autoscaled" {
  variables {
    name       = run.setup.name
    hash_key   = "pk"
    range_key  = "sk"
    attributes = { pk = "S", sk = "S", status = "S" }
    tags       = run.setup.tags

    billing_mode = "PROVISIONED"
    stream       = { view_type = "NEW_AND_OLD_IMAGES" }

    global_secondary_indexes = {
      by_status = { hash_key = "status", projection_type = "KEYS_ONLY" }
    }

    # Write is autoscaled on the table and the index, as DynamoDB requires for
    # replicas; read is autoscaled too so the replica inherits a scaler.
    autoscaling = {
      table = {
        read  = { min_capacity = 1, max_capacity = 4 }
        write = { min_capacity = 1, max_capacity = 4 }
      }
      indexes = {
        by_status = {
          read  = { min_capacity = 1, max_capacity = 4 }
          write = { min_capacity = 1, max_capacity = 4 }
        }
      }
    }

    replicas = {
      (run.setup.replica_region) = { deletion_protection_enabled = false }
    }

    deletion_protection_enabled = false
  }

  expect_failures = [check.deletion_protection_disabled]

  assert {
    condition     = length(aws_dynamodb_table.autoscaled) == 1 && length(aws_dynamodb_table_replica.this) == 1
    error_message = "The autoscaled table and its separate replica must both exist after a single apply."
  }

  assert {
    condition     = length(output.autoscaling_policy_arns) == 4 && contains(keys(output.autoscaling_target_resource_ids), "table_write") && contains(keys(output.autoscaling_target_resource_ids), "index_by_status_write")
    error_message = "Write autoscaling must have been registered on the table and the index before the replica."
  }

  assert {
    condition     = keys(output.replica_arns) == [run.setup.replica_region] && startswith(output.replica_arns[run.setup.replica_region], "arn:") && strcontains(output.replica_arns[run.setup.replica_region], ":${run.setup.replica_region}:")
    error_message = "The replica must exist in the second region and be exposed by replica_arns."
  }

  assert {
    condition     = aws_dynamodb_table_replica.this[run.setup.replica_region].global_table_arn == output.arn
    error_message = "The replica must belong to the table under test."
  }
}
