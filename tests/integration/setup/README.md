# Integration fixtures

Disposable prerequisites for the integration suites in the parent directory: a
table name with a random suffix and the caller's account identity, used as the
principal of the resource policy under test. `terraform test` resolves them in
the caller's own account before the module under test and discards them
afterwards. They are not a deployable pattern and are excluded from policy
scans (see `.checkov.yml` and `trivy.yaml` at the repository root).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0, < 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6.0, < 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [random_id.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for the table name; a random suffix is appended so concurrent runs never collide. | `string` | `"dynamodb-it"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the table under test in addition to the identifying defaults. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | Account the suite runs in, resolved from the caller's credentials. |
| <a name="output_account_root_arn"></a> [account\_root\_arn](#output\_account\_root\_arn) | Root principal ARN of the account, granted read access by the resource policy under test. |
| <a name="output_name"></a> [name](#output\_name) | Unique table name for the suite. |
| <a name="output_tags"></a> [tags](#output\_tags) | Identifying tags shared with the table under test. |
<!-- END_TF_DOCS -->
