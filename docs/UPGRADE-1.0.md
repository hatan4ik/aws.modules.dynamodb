# Upgrading from 0.1.x to 1.0.0

## What changed and why

Version 0.1.x provisioned one encrypted table with a typed `attributes` map, global secondary indexes, TTL, point-in-time recovery, and deletion protection, and carried its two cross-input rules on a `terraform_data.input_contract` resource. Version 1.0.0 still provisions one table per call, but reshapes the interface around feature groups (`ttl`, `server_side_encryption`, `point_in_time_recovery`, `stream`, `autoscaling`, `replicas`, `resource_policy_statements`), adds local secondary indexes, streams, replicas, table class, on-demand limits, Application Auto Scaling, a resource-based policy, Contributor Insights, and a Kinesis destination, enforces the attribute contract and every other cross-input rule at plan time on the table itself, and drops the phantom `terraform_data` resource. The reasons, and the table of 0.1.x behaviours that were replaced, are in [DESIGN.md](DESIGN.md). This guide gets an existing 0.1.x consumer onto 1.0.0 without replacing the table.

## Input mapping

Root inputs of 0.1.2:

| 0.1.x input | 1.0.0 equivalent |
| --- | --- |
| `name` | `name`, unchanged. Now validated: 3 to 255 characters of `[a-zA-Z0-9_.-]`. |
| `hash_key`, `range_key` | `hash_key`, `range_key`, unchanged. |
| `attributes = { name = { type = "S" } }` | `attributes = { name = "S" }`: a map of attribute name to type. Declare exactly the attributes used by the primary key and by index keys; an unused attribute now fails the plan (the API rejected it at apply time before). |
| `billing_mode` | `billing_mode`, unchanged. |
| `read_capacity`, `write_capacity` | `read_capacity`, `write_capacity`, unchanged. Now rejected on a `PAY_PER_REQUEST` table instead of silently dropped, and required on every GSI of a `PROVISIONED` table unless `autoscaling` covers it. |
| `global_secondary_indexes` | `global_secondary_indexes`, same keys and the same `hash_key`, `range_key`, `projection_type`, `non_key_attributes`, `read_capacity`, and `write_capacity` attributes, plus optional `on_demand_throughput`. `INCLUDE` now requires `non_key_attributes` and the other projections forbid them. |
| `ttl_attribute_name` | `ttl = { attribute_name = "<name>" }`. Leave `ttl` null (the default) when you set no attribute before. |
| `kms_key_arn` | `server_side_encryption = { kms_key_arn = "<arn>" }`. Leave the default (`{}`) for the AWS owned key. The ARN must be a full key ARN, not an alias. |
| `point_in_time_recovery_enabled` | `point_in_time_recovery = { enabled = <bool> }` (default `{ enabled = true }`). |
| `deletion_protection_enabled` | `deletion_protection_enabled`, unchanged. |
| `tags` | `tags`, unchanged shape. The module now adds a `Name` tag equal to `name`. |

Outputs `id`, `arn`, and `stream_arn` keep their names. `stream_arn` is `null` unless `stream` is declared; 0.1.x had no streams, so its value was already null. New outputs are listed in the README.

Nothing in 0.1.x maps to `autoscaling`, `replicas`, `local_secondary_indexes`, `stream`, `table_class`, `on_demand_throughput`, `resource_policy_statements`, `contributor_insights_*`, `kinesis_*`, or `timeouts`; they are new and default to off.

A complete rewrite for a consumer whose 0.1.x block was `module "orders"`:

```hcl
# 0.1.x
module "orders" {
  source = "git::https://github.com/hatan4ik/aws.modules.dynamodb.git?ref=v0.1.2"

  name      = "orders"
  hash_key  = "pk"
  range_key = "sk"
  attributes = {
    pk     = { type = "S" }
    sk     = { type = "S" }
    status = { type = "S" }
  }
  global_secondary_indexes = {
    by_status = { hash_key = "status", range_key = "sk", projection_type = "KEYS_ONLY" }
  }
  ttl_attribute_name             = "expires_at"
  kms_key_arn                    = var.kms_key_arn
  point_in_time_recovery_enabled = true
  deletion_protection_enabled    = true
  tags                           = var.tags
}

# 1.0.0
module "orders" {
  source = "git::https://github.com/hatan4ik/aws.modules.dynamodb.git?ref=<commit-sha>" # v1.0.0

  name       = "orders"
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S", status = "S" }

  global_secondary_indexes = {
    by_status = { hash_key = "status", range_key = "sk", projection_type = "KEYS_ONLY" }
  }

  ttl                    = { attribute_name = "expires_at" }
  server_side_encryption = { kms_key_arn = var.kms_key_arn }
  point_in_time_recovery = { enabled = true }

  deletion_protection_enabled = true
  tags                        = var.tags
}
```

## Preserving the existing table

The table's identity is its `name`, `hash_key`, `range_key`, and attribute definitions, and a GSI's identity is its key (the map key) with its keys and projection. Keep every one of them exactly as before and the table and its indexes are updated in place or not touched at all:

| Setting | 0.1.x | 1.0.0 input |
| --- | --- | --- |
| Table name | `name` | `name`, the same string. |
| Key schema | `hash_key`, `range_key` | The same values. Changing either replaces the table. |
| Attribute definitions | `attributes` keys and `type` values | The same keys with the type as the value. Changing an attribute's type replaces the table. |
| Global secondary indexes | map keys, `hash_key`, `range_key`, `projection_type`, `non_key_attributes` | The same keys and values. Changing an index's keys or projection replaces that index. |
| Capacities | `read_capacity`, `write_capacity`, GSI capacities | The same values on a `PROVISIONED` table. |
| Encryption key | `kms_key_arn` | `server_side_encryption.kms_key_arn` with the same ARN. Switching between the AWS owned key and a customer managed key is an in-place update. |
| TTL | `ttl_attribute_name` | `ttl.attribute_name` with the same attribute. |

What will change even with those inputs, all expected and all in place:

- Tags gain `Name = <name>` unless you already set it.
- `table_class = "STANDARD"` is now sent explicitly, which matches the value every 0.1.x table has.
- When no TTL attribute was set, 0.1.x rendered a disabled `ttl` block; 1.0.0 renders none. The provider treats the two the same.
- `terraform_data.input_contract` is destroyed. It touched nothing in AWS.

## State moves

Old addresses are those of 0.1.2 under `module.orders`. New addresses are under the same module block.

| 0.1.2 address | 1.0.0 address |
| --- | --- |
| `module.orders.aws_dynamodb_table.this` | `module.orders.aws_dynamodb_table.this[0]` |
| `module.orders.aws_dynamodb_table.this` (when adopting `autoscaling` in the same change) | `module.orders.aws_dynamodb_table.autoscaled[0]` |
| `module.orders.terraform_data.input_contract` | Not moved. Destroyed. |

Ready to paste into your root configuration. Use exactly one of the two `moved` blocks.

```hcl
# Without autoscaling
moved {
  from = module.orders.aws_dynamodb_table.this
  to   = module.orders.aws_dynamodb_table.this[0]
}

# Or, when the same change adds autoscaling to a PROVISIONED table
moved {
  from = module.orders.aws_dynamodb_table.this
  to   = module.orders.aws_dynamodb_table.autoscaled[0]
}
```

The same block applies later whenever you toggle `autoscaling` between `null` and an object: `from = module.orders.aws_dynamodb_table.this[0]` to `to = module.orders.aws_dynamodb_table.autoscaled[0]`, or the reverse.

## Procedure

1. Pin the 1.0.0 release: copy the commit SHA of tag `v1.0.0` into `?ref=<commit-sha>` and put the tag in a trailing comment.
2. Rewrite the module block as shown above: `attributes` as a map of strings, `ttl`, `server_side_encryption`, and `point_in_time_recovery` as objects, everything else unchanged.
3. Keep the identity-preserving inputs (`name`, `hash_key`, `range_key`, `attributes`, index keys and projections, capacities, the KMS key ARN, the TTL attribute) exactly as they were.
4. Add the `moved` block for the table.
5. Run `terraform init -upgrade` to fetch the new module source, then `terraform plan`.
6. Verify the plan. There must be no replacement or destruction of `aws_dynamodb_table`. Expect: `aws_dynamodb_table.this[0]` updated in place (tags, possibly `table_class` and `ttl`), and `terraform_data.input_contract` destroyed. If the table shows `must be replaced`, compare `name`, `hash_key`, `range_key`, and the attribute types with the table above before applying. A plan error naming an attribute means `attributes` declares one that no key uses, or a key uses one that is not declared; fix the map rather than the key.
7. Apply.
8. Remove the `moved` block in a later change once every workspace that used 0.1.x has applied the upgrade.
