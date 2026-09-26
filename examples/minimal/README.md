# Minimal table

The smallest working call of `aws.modules.dynamodb`: a table named `orders`
with a composite primary key (`pk`, `sk`) and nothing else declared. Everything
keeps the module's secure defaults: on-demand billing, encryption at rest on the
AWS owned key, point-in-time recovery, deletion protection, the `STANDARD` table
class, no stream, no indexes. Start here to see exactly what a table needs
before layering on features.

The one rule that catches people is the `attributes` map: declare exactly the
attributes used by the primary key and by index keys, because DynamoDB rejects
both an undeclared key attribute and a declared attribute that no key uses. The
module enforces both at plan time.

## Run

```sh
terraform init
terraform plan
```

Deletion protection is on, so a later `terraform destroy` fails until the table
is applied once with `deletion_protection_enabled = false`.

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
| <a name="input_name"></a> [name](#input\_name) | Table name. | `string` | `"orders"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the table. | `string` | `"us-east-1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the table. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_table_arn"></a> [table\_arn](#output\_table\_arn) | ARN of the table. |
| <a name="output_table_id"></a> [table\_id](#output\_table\_id) | ID of the table. |
| <a name="output_table_name"></a> [table\_name](#output\_table\_name) | Name of the table. |
<!-- END_TF_DOCS -->
