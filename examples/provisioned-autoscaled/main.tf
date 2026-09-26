provider "aws" {
  region = var.region
}

module "table" {
  source = "../../"

  name       = var.name
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S", status = "S" }
  tags       = var.tags

  global_secondary_indexes = {
    by_status = {
      hash_key        = "status"
      projection_type = "KEYS_ONLY"
      # No capacities: the index starts at its autoscaling minimums.
    }
  }

  billing_mode = "PROVISIONED"

  # Initial capacities of the table. They must lie within the autoscaling
  # bounds below; Application Auto Scaling owns the values from then on and
  # the module ignores the resulting drift.
  read_capacity  = 10
  write_capacity = 5

  autoscaling = {
    table = {
      read  = { min_capacity = 5, max_capacity = 200 }
      write = { min_capacity = 5, max_capacity = 100, target_utilization = 60, scale_in_cooldown = 600 }
    }
    indexes = {
      by_status = {
        read  = { min_capacity = 1, max_capacity = 50 }
        write = { min_capacity = 1, max_capacity = 25 }
      }
    }
  }

  contributor_insights_enabled = true
}
