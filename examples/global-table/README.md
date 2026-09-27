# Global table

A multi-region (global) table: one on-demand table in the provider region with
a stream of new and old images and a replica in each region named in
`replica_kms_key_arns`. The table and every replica are encrypted with a
customer managed key in their own region; point-in-time recovery, deletion
protection, and tags are inherited from the table by every replica.

The module enforces the rules that otherwise fail at apply time: replicas need
`stream = { view_type = "NEW_AND_OLD_IMAGES" }`, on-demand billing or
autoscaling, and, when the table uses a customer managed key, a regional key on
each replica. Replicas are declared as data, so adding a region is adding a map
entry; removing one removes that replica only.

## Run

```hcl
kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"

replica_kms_key_arns = {
  "eu-west-1"      = "arn:aws:kms:eu-west-1:123456789012:key/22222222-2222-2222-2222-222222222222"
  "ap-southeast-2" = "arn:aws:kms:ap-southeast-2:123456789012:key/33333333-3333-3333-3333-333333333333"
}
```

```sh
terraform init && terraform plan
```

Replica creation takes several minutes per region; the module's default
timeouts allow for it.

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
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Customer managed KMS key in the primary region that encrypts the table. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Table name, shared by every replica. | `string` | `"orders-global"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region of the primary table; the provider region. | `string` | `"us-east-1"` | no |
| <a name="input_replica_kms_key_arns"></a> [replica\_kms\_key\_arns](#input\_replica\_kms\_key\_arns) | Replica regions keyed by region name, each with the customer managed KMS key ARN in that region. Two regions make a global table; add or remove a key to add or remove a replica. | `map(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the table and propagated to every replica. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_replica_arns"></a> [replica\_arns](#output\_replica\_arns) | Replica table ARNs keyed by region. |
| <a name="output_stream_arn"></a> [stream\_arn](#output\_stream\_arn) | ARN of the primary table's stream. |
| <a name="output_table_arn"></a> [table\_arn](#output\_table\_arn) | ARN of the primary table. |
<!-- END_TF_DOCS -->
