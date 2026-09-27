# Multiple tables

Creates a fleet of tables from one root module by using `for_each` on the
module block. `aws.modules.dynamodb` provisions exactly one table per call on
purpose: a table is the unit that gets its own key schema, indexes, stream,
policy, and lifecycle, and a plan error names the one table that caused it.
Fleets are therefore expressed in the caller, as a map of table
specifications, not as a list inside the module.

Each entry supplies its keys, attribute definitions, optional global secondary
indexes, an optional TTL attribute, and an optional stream view type; the
module derives `<name_prefix>-<key>` and keeps every secure default. Adding a
table is adding a map entry; removing one destroys exactly that table (once
its deletion protection is off). Because every table has its own module
instance, you can still `-target` or `moved` a single one.

## Run

Declare the fleet in a `terraform.tfvars`:

```hcl
tables = {
  orders = {
    hash_key   = "pk"
    range_key  = "sk"
    attributes = { pk = "S", sk = "S", status = "S" }
    global_secondary_indexes = {
      by_status = { hash_key = "status", projection_type = "KEYS_ONLY" }
    }
    stream_view_type = "NEW_AND_OLD_IMAGES"
  }
  sessions = {
    hash_key      = "session_id"
    attributes    = { session_id = "S" }
    ttl_attribute = "expires_at"
  }
}
```

```sh
terraform init && terraform plan
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_table"></a> [table](#module\_table) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for every table name; the table key is appended (<prefix>-<key>). | `string` | `"platform"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of every table. | `string` | `"us-east-1"` | no |
| <a name="input_tables"></a> [tables](#input\_tables) | Tables to create, keyed by a short name that becomes the suffix of the table name. attributes must declare exactly the attributes used by the keys and index keys. | <pre>map(object({<br/>    hash_key   = string<br/>    range_key  = optional(string)<br/>    attributes = map(string)<br/>    global_secondary_indexes = optional(map(object({<br/>      hash_key           = string<br/>      range_key          = optional(string)<br/>      projection_type    = string<br/>      non_key_attributes = optional(set(string))<br/>    })), {})<br/>    ttl_attribute    = optional(string)<br/>    stream_view_type = optional(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every table. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_stream_arns"></a> [stream\_arns](#output\_stream\_arns) | Stream ARNs keyed by table key; null for tables without a stream. |
| <a name="output_table_arns"></a> [table\_arns](#output\_table\_arns) | Table ARNs keyed by table key. |
| <a name="output_table_names"></a> [table\_names](#output\_table\_names) | Table names keyed by table key. |
<!-- END_TF_DOCS -->
