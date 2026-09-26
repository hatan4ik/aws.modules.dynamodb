# autoscaling

Owns Application Auto Scaling for one PROVISIONED DynamoDB table: a scalable target and a target-tracking policy for each scaled dimension of the table and of its global secondary indexes. It is a separate module because scaling shape evolves independently of the table, and because you may need to scale a table the root module did not create.

## Usage

```hcl
module "autoscaling" {
  source = "git::https://github.com/hatan4ik/aws.modules.dynamodb.git//modules/autoscaling?ref=<commit-sha>" # v1.0.0

  table_name = "orders"

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

  tags = { Environment = "prod" }
}
```

## Behaviour

- Dimensions. Every non-null `table.read`, `table.write`, `indexes.<name>.read`, and `indexes.<name>.write` becomes one dimension keyed `table_read`, `table_write`, `index_<name>_read`, or `index_<name>_write`. Nothing else is scaled, and at least one dimension must be declared.
- Target. `table/<table_name>` or `table/<table_name>/index/<name>` in the `dynamodb` namespace on `dynamodb:table:ReadCapacityUnits`, `dynamodb:table:WriteCapacityUnits`, `dynamodb:index:ReadCapacityUnits`, or `dynamodb:index:WriteCapacityUnits`, bounded by `min_capacity` and `max_capacity` (`1 <= min <= max`).
- Policy. One `TargetTrackingScaling` policy per dimension named `<table_name>-<dimension>`, tracking the predefined `DynamoDBReadCapacityUtilization` or `DynamoDBWriteCapacityUtilization` metric at `target_utilization` percent (20 to 90, default 70). `scale_in_cooldown` defaults to 300 seconds and `scale_out_cooldown` to 60: conservative scale-in, fast scale-out.
- The table must be `PROVISIONED`; Application Auto Scaling rejects on-demand tables at apply time. Set the table's initial capacities to the dimension minimums and ignore later capacity drift, as the root module does with its `autoscaled` table variant.
- Tags are applied to every scalable target.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_appautoscaling_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_indexes"></a> [indexes](#input\_indexes) | Global secondary index dimensions to scale, keyed by index name. Each value has the same read and write shape as table; at least one of the two must be set. | <pre>map(object({<br/>    read = optional(object({<br/>      min_capacity       = number<br/>      max_capacity       = number<br/>      target_utilization = optional(number, 70)<br/>      scale_in_cooldown  = optional(number, 300)<br/>      scale_out_cooldown = optional(number, 60)<br/>    }))<br/>    write = optional(object({<br/>      min_capacity       = number<br/>      max_capacity       = number<br/>      target_utilization = optional(number, 70)<br/>      scale_in_cooldown  = optional(number, 300)<br/>      scale_out_cooldown = optional(number, 60)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_table"></a> [table](#input\_table) | Table-level dimensions to scale. Each of read and write is null (not scaled) or an object with min\_capacity, max\_capacity, target\_utilization (percent, default 70), scale\_in\_cooldown (seconds, default 300), and scale\_out\_cooldown (seconds, default 60). | <pre>object({<br/>    read = optional(object({<br/>      min_capacity       = number<br/>      max_capacity       = number<br/>      target_utilization = optional(number, 70)<br/>      scale_in_cooldown  = optional(number, 300)<br/>      scale_out_cooldown = optional(number, 60)<br/>    }))<br/>    write = optional(object({<br/>      min_capacity       = number<br/>      max_capacity       = number<br/>      target_utilization = optional(number, 70)<br/>      scale_in_cooldown  = optional(number, 300)<br/>      scale_out_cooldown = optional(number, 60)<br/>    }))<br/>  })</pre> | `null` | no |
| <a name="input_table_name"></a> [table\_name](#input\_table\_name) | Name of the PROVISIONED DynamoDB table to scale. Also prefixes policy names. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every scalable target. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_policy_arns"></a> [policy\_arns](#output\_policy\_arns) | Target-tracking policy ARNs keyed by dimension. |
| <a name="output_target_arns"></a> [target\_arns](#output\_target\_arns) | Scalable target ARNs keyed by dimension. |
| <a name="output_target_resource_ids"></a> [target\_resource\_ids](#output\_target\_resource\_ids) | Application Auto Scaling resource IDs keyed by dimension (table\_read, table\_write, index\_<name>\_read, index\_<name>\_write). |
<!-- END_TF_DOCS -->
