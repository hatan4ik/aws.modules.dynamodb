# Complete table

Every major feature of `aws.modules.dynamodb` in one on-demand table: a
composite primary key, two global secondary indexes (one `ALL` projection, one
`INCLUDE` projection with its own on-demand cap), a local secondary index,
table-level on-demand throughput limits, a customer managed KMS key, a 14-day
point-in-time recovery window, deletion protection, TTL, a stream of new and
old images, a Kinesis Data Streams destination with microsecond timestamps,
CloudWatch Contributor Insights on the table and on one index, a resource-based
policy with an Allow and a conditioned Deny, and explicit timeouts. Use it as a
reference for the shape of each input, then copy the parts you need.

Two details are easy to miss. The `attributes` map lists exactly the five
attributes used by the primary key and the index keys; `expires_at` is the TTL
attribute and is deliberately not declared, because it is not a key. And the
`DenyOutsideOrganization` statement uses a wildcard principal, which the module
only accepts together with a condition.

Autoscaling and replicas are not shown here because they need a PROVISIONED
table and a multi-region setup respectively: see
[`examples/provisioned-autoscaled`](../provisioned-autoscaled) and
[`examples/global-table`](../global-table).

## Run

The example takes several environment-specific inputs, so a `terraform.tfvars`
is easier than `-var` flags:

```hcl
kms_key_arn        = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"
kinesis_stream_arn = "arn:aws:kinesis:us-east-1:123456789012:stream/orders-changes"
analytics_role_arn = "arn:aws:iam::123456789012:role/analytics-reader"
organization_id    = "o-abcdef1234"
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
| <a name="input_analytics_role_arn"></a> [analytics\_role\_arn](#input\_analytics\_role\_arn) | IAM role granted read-only access to the table and its indexes through the resource-based policy. | `string` | n/a | yes |
| <a name="input_kinesis_stream_arn"></a> [kinesis\_stream\_arn](#input\_kinesis\_stream\_arn) | Kinesis Data Stream that receives item-level changes from the table. | `string` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Customer managed KMS key that encrypts the table. Its key policy must allow the DynamoDB service to use it on behalf of the account. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Table name; also the Name tag. | `string` | `"orders"` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | AWS Organizations ID (o-...) outside of which every principal is denied by the resource-based policy. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the table. | `string` | `"us-east-1"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the table and propagated to replicas and autoscaling targets. | `map(string)` | <pre>{<br/>  "Environment": "production",<br/>  "Team": "orders"<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_global_secondary_index_arns"></a> [global\_secondary\_index\_arns](#output\_global\_secondary\_index\_arns) | Global secondary index ARNs keyed by index name. |
| <a name="output_local_secondary_index_arns"></a> [local\_secondary\_index\_arns](#output\_local\_secondary\_index\_arns) | Local secondary index ARNs keyed by index name. |
| <a name="output_resource_policy"></a> [resource\_policy](#output\_resource\_policy) | Rendered resource-based policy document. |
| <a name="output_stream_arn"></a> [stream\_arn](#output\_stream\_arn) | ARN of the DynamoDB stream. |
| <a name="output_stream_label"></a> [stream\_label](#output\_stream\_label) | Timestamp label of the DynamoDB stream. |
| <a name="output_table_arn"></a> [table\_arn](#output\_table\_arn) | ARN of the table. |
| <a name="output_table_name"></a> [table\_name](#output\_table\_name) | Name of the table. |
<!-- END_TF_DOCS -->
