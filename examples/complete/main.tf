provider "aws" {
  region = var.region
}

module "table" {
  source = "../../"

  name = var.name
  tags = var.tags

  # ------------------------------------------------------------- keys
  hash_key  = "pk"
  range_key = "sk"

  # Exactly the attributes used by the primary key and by index keys.
  attributes = {
    pk         = "S"
    sk         = "S"
    status     = "S"
    created_at = "N"
    customer   = "S"
  }

  global_secondary_indexes = {
    by_status = {
      hash_key        = "status"
      range_key       = "created_at"
      projection_type = "ALL"
    }
    by_customer = {
      hash_key           = "customer"
      range_key          = "created_at"
      projection_type    = "INCLUDE"
      non_key_attributes = ["status"]
      # Caps this index independently of the table.
      on_demand_throughput = { max_read_request_units = 500 }
    }
  }

  local_secondary_indexes = {
    by_created = {
      range_key       = "created_at"
      projection_type = "KEYS_ONLY"
    }
  }

  # ------------------------------------------------------- throughput
  billing_mode = "PAY_PER_REQUEST"
  table_class  = "STANDARD"

  on_demand_throughput = {
    max_read_request_units  = 4000
    max_write_request_units = 1000
  }

  # -------------------------------------------------- data protection
  server_side_encryption = { kms_key_arn = var.kms_key_arn }

  point_in_time_recovery = {
    enabled                 = true
    recovery_period_in_days = 14
  }

  deletion_protection_enabled = true

  ttl = { attribute_name = "expires_at" }

  # ------------------------------------------------------ integration
  stream = { view_type = "NEW_AND_OLD_IMAGES" }

  kinesis_stream_arn                               = var.kinesis_stream_arn
  kinesis_approximate_creation_date_time_precision = "MICROSECOND"

  contributor_insights_enabled = true
  contributor_insights_indexes = ["by_status"]

  # Resource-based policy: an Allow for one reader role on the table and every
  # index (the default resources), and a Deny for any principal outside the
  # organisation. The module sorts the rendered document so it only changes
  # when a statement does.
  resource_policy_statements = {
    AllowAnalyticsRead = {
      principals = { AWS = [var.analytics_role_arn] }
      actions    = ["dynamodb:BatchGetItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
    }
    DenyOutsideOrganization = {
      effect     = "Deny"
      principals = { AWS = ["*"] }
      actions    = ["dynamodb:*"]
      conditions = [
        { test = "StringNotEquals", variable = "aws:PrincipalOrgID", values = [var.organization_id] },
      ]
    }
  }

  # ------------------------------------------------------- operations
  timeouts = {
    create = "30m"
    update = "60m"
    delete = "30m"
  }
}
