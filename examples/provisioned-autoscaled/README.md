# Provisioned table with autoscaling

A PROVISIONED table whose read and write capacity, and the capacity of its
global secondary index, are managed by Application Auto Scaling. The table
starts at 10 read and 5 write units, the index at its dimension minimums, and
four target-tracking policies keep utilisation at 70 percent (60 percent for
table writes, with a longer scale-in cooldown). CloudWatch Contributor Insights
is on so hot keys are visible while the scaler works.

Declaring `autoscaling` selects the module's `aws_dynamodb_table.autoscaled[0]`
variant, which ignores later changes to `read_capacity`, `write_capacity`, and
`global_secondary_index`, so the values the scaler writes never show as drift.
Explicit initial capacities must lie within their dimension's bounds; the
module rejects a plan where they do not. Removing `autoscaling` later changes
the resource address back to `aws_dynamodb_table.this[0]`: add a `moved` block
(see [docs/UPGRADE-1.0.md](../../docs/UPGRADE-1.0.md)) so the table is not
replaced.

## Run

```sh
terraform init
terraform plan
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
| <a name="input_name"></a> [name](#input\_name) | Table name; also the prefix of the autoscaling policy names. | `string` | `"orders-provisioned"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the table. | `string` | `"us-east-1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the table and to every scalable target. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_autoscaling_policy_arns"></a> [autoscaling\_policy\_arns](#output\_autoscaling\_policy\_arns) | Target-tracking policy ARNs keyed by dimension. |
| <a name="output_autoscaling_target_resource_ids"></a> [autoscaling\_target\_resource\_ids](#output\_autoscaling\_target\_resource\_ids) | Application Auto Scaling resource IDs keyed by dimension. |
| <a name="output_table_arn"></a> [table\_arn](#output\_table\_arn) | ARN of the table. |
| <a name="output_table_name"></a> [table\_name](#output\_table\_name) | Name of the table. |
<!-- END_TF_DOCS -->
