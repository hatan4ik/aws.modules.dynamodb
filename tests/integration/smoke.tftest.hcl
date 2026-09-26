# Integration suite: real apply in the caller's own account.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow). Nothing is hard-coded: the setup module resolves a unique table
# name and the caller's account, the module is applied as an on-demand table
# with a GSI, TTL, point-in-time recovery, a stream, and a resource policy, the
# results are asserted against the real API, and everything is destroyed at
# the end of the file. Deletion protection is off for that reason only.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix = "dynamodb-it"
  }
}

run "smoke" {
  variables {
    name       = run.setup.name
    hash_key   = "pk"
    range_key  = "sk"
    attributes = { pk = "S", sk = "S", status = "S" }
    tags       = run.setup.tags

    global_secondary_indexes = {
      by_status = { hash_key = "status", range_key = "sk", projection_type = "KEYS_ONLY" }
    }

    ttl    = { attribute_name = "expires_at" }
    stream = { view_type = "NEW_AND_OLD_IMAGES" }

    point_in_time_recovery = { enabled = true }

    # Off so terraform test can destroy the table at the end of the file; the
    # advisory check that warns about it is expected below.
    deletion_protection_enabled = false

    resource_policy_statements = {
      AllowAccountRead = {
        principals = { AWS = [run.setup.account_root_arn] }
        actions    = ["dynamodb:GetItem", "dynamodb:Query"]
      }
    }
  }

  expect_failures = [check.deletion_protection_disabled]

  assert {
    condition     = length(aws_dynamodb_table.this) == 1 && aws_dynamodb_table.this[0].billing_mode == "PAY_PER_REQUEST" && aws_dynamodb_table.this[0].table_class == "STANDARD"
    error_message = "The plain table variant must exist as an on-demand STANDARD table."
  }

  assert {
    condition     = output.name == run.setup.name && output.id == run.setup.name && startswith(output.arn, "arn:")
    error_message = "Outputs must reflect the fixture name and a real table ARN."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].point_in_time_recovery[0].enabled == true && aws_dynamodb_table.this[0].server_side_encryption[0].enabled == true && aws_dynamodb_table.this[0].ttl[0].enabled == true && aws_dynamodb_table.this[0].ttl[0].attribute_name == "expires_at"
    error_message = "Point-in-time recovery, encryption at rest, and TTL must have been accepted by the API."
  }

  assert {
    condition     = output.stream_arn != null && startswith(output.stream_arn, "arn:") && output.stream_label != null
    error_message = "The stream must have been created with an ARN and a label."
  }

  assert {
    condition     = output.global_secondary_index_arns["by_status"] == "${output.arn}/index/by_status" && length(output.local_secondary_index_arns) == 0
    error_message = "The GSI ARN must derive from the real table ARN."
  }

  assert {
    condition     = length(aws_dynamodb_resource_policy.this) == 1 && aws_dynamodb_resource_policy.this[0].resource_arn == output.arn && jsondecode(aws_dynamodb_resource_policy.this[0].policy).Statement[0].Resource == [output.arn, "${output.arn}/index/*"]
    error_message = "The resource policy must have been attached to the table with the default table-and-indexes resources."
  }

  assert {
    condition     = aws_dynamodb_table.this[0].tags["IntegrationTest"] == "aws.modules.dynamodb" && aws_dynamodb_table.this[0].tags["Name"] == run.setup.name
    error_message = "Fixture tags and the Name tag must be applied."
  }
}
