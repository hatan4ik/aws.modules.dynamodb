mock_provider "aws" {
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:us-east-1:123456789012:table/orders"
    }
  }
}

variables {
  name       = "orders"
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S" }
}

run "renders_sorted_null_free_statements" {
  command = plan

  variables {
    resource_policy_statements = {
      ReadOnly = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/reader-b", "arn:aws:iam::123456789012:role/reader-a"] }
        actions    = ["dynamodb:Query", "dynamodb:GetItem", "dynamodb:BatchGetItem"]
        resources  = ["arn:aws:dynamodb:us-east-1:123456789012:table/orders"]
      }
      DenyInsecureTransport = {
        effect     = "Deny"
        principals = { AWS = ["*"] }
        actions    = ["dynamodb:*"]
        resources  = ["arn:aws:dynamodb:us-east-1:123456789012:table/orders", "arn:aws:dynamodb:us-east-1:123456789012:table/orders/index/*"]
        conditions = [
          { test = "Bool", variable = "aws:SecureTransport", values = ["false"] },
          { test = "StringNotEquals", variable = "aws:PrincipalOrgID", values = ["o-example"] },
          { test = "StringNotEquals", variable = "aws:PrincipalAccount", values = ["123456789012", "111111111111"] },
        ]
      }
    }
  }

  assert {
    condition     = length(aws_dynamodb_resource_policy.this) == 1 && aws_dynamodb_resource_policy.this[0].policy == output.resource_policy && jsondecode(output.resource_policy).Version == "2012-10-17"
    error_message = "The resource policy must be created from the rendered document and exposed as an output."
  }

  assert {
    condition     = [for statement in jsondecode(output.resource_policy).Statement : statement.Sid] == ["DenyInsecureTransport", "ReadOnly"]
    error_message = "Statements must be sorted by Sid."
  }

  assert {
    condition     = jsondecode(output.resource_policy).Statement[1].Effect == "Allow" && jsondecode(output.resource_policy).Statement[1].Principal.AWS == ["arn:aws:iam::123456789012:role/reader-a", "arn:aws:iam::123456789012:role/reader-b"] && jsondecode(output.resource_policy).Statement[1].Action == ["dynamodb:BatchGetItem", "dynamodb:GetItem", "dynamodb:Query"] && jsondecode(output.resource_policy).Statement[1].Resource == ["arn:aws:dynamodb:us-east-1:123456789012:table/orders"]
    error_message = "Principals, actions, and resources must be sorted and Effect must default to Allow."
  }

  assert {
    condition     = !contains(keys(jsondecode(output.resource_policy).Statement[1]), "Condition")
    error_message = "A statement without conditions must not render a Condition key."
  }

  assert {
    condition     = jsondecode(output.resource_policy).Statement[0].Effect == "Deny" && jsondecode(output.resource_policy).Statement[0].Principal.AWS == ["*"] && jsondecode(output.resource_policy).Statement[0].Condition.Bool["aws:SecureTransport"] == ["false"] && jsondecode(output.resource_policy).Statement[0].Condition.StringNotEquals["aws:PrincipalOrgID"] == ["o-example"] && jsondecode(output.resource_policy).Statement[0].Condition.StringNotEquals["aws:PrincipalAccount"] == ["111111111111", "123456789012"]
    error_message = "Conditions must be grouped by test operator with sorted values."
  }
}

run "defaults_resources_to_the_table_and_its_indexes" {
  command = apply

  variables {
    resource_policy_statements = {
      ReadOnly = {
        principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] }
        actions    = ["dynamodb:GetItem"]
      }
    }
  }

  assert {
    condition     = jsondecode(aws_dynamodb_resource_policy.this[0].policy).Statement[0].Resource == ["arn:aws:dynamodb:us-east-1:123456789012:table/orders", "arn:aws:dynamodb:us-east-1:123456789012:table/orders/index/*"] && aws_dynamodb_resource_policy.this[0].resource_arn == "arn:aws:dynamodb:us-east-1:123456789012:table/orders"
    error_message = "A statement without resources must cover the table and every index."
  }
}
