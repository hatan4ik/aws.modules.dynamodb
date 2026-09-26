# aws.modules.dynamodb

Provisions one Amazon DynamoDB table together with everything a production table needs: key schema and attribute definitions, global and local secondary indexes, on-demand or provisioned throughput with Application Auto Scaling, DynamoDB Streams, multi-region replicas, TTL, point-in-time recovery, encryption at rest, a resource-based policy, CloudWatch Contributor Insights, and a Kinesis Data Streams destination. It is secure by default and explicit by declaration: every feature is a typed optional input that renders to exactly one resource or block, every cross-input rule fails at plan time naming the attribute, index, or region it rejects, and the module performs no data-source reads. Requires Terraform >= 1.7 and the AWS provider >= 6.35, < 7.

## Why this module

What you get without setting anything:

- On-demand billing (`PAY_PER_REQUEST`) in the `STANDARD` table class. Provisioned tables declare capacities or an `autoscaling` object, and the module checks that every dimension is covered.
- Encryption at rest that cannot be turned off. The AWS owned key by default; your customer managed key with `server_side_encryption.kms_key_arn`, and a regional key on every replica when you use one.
- Point-in-time recovery on, with an optional shorter `recovery_period_in_days`.
- Deletion protection on. Advisory `check` blocks warn on every plan while deletion protection or point-in-time recovery is off.
- Nothing else: no stream, index, replica, policy, Contributor Insights, or Kinesis destination exists until you declare it.
- The attribute contract enforced at plan time: every key attribute of the table, of a GSI, or of an LSI must be declared in `attributes`, and every declared attribute must be used by a key, because DynamoDB rejects both at apply time.
- Plan-time validation of everything else that otherwise fails at apply: projection types and their `non_key_attributes`, capacities against `billing_mode` and autoscaling bounds, on-demand limits, the LSI limit and its `range_key` requirement, the TTL attribute, replica prerequisites, KMS and Kinesis ARN shapes, and resource-policy statements (a wildcard principal needs a condition).
- Only a `Name` tag is added. Caller tags pass through to the table, to replicas, and to autoscaling targets.
- Outputs for every identifier a consumer needs: table ARN, stream ARN and label, index ARNs, replica ARNs, autoscaling resource IDs and policy ARNs, and the rendered policy.

## Quick start

```hcl
module "orders" {
  source = "git::https://github.com/hatan4ik/aws.modules.dynamodb.git?ref=<commit-sha>" # v1.0.0

  name       = "orders"
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S", status = "S" }

  global_secondary_indexes = {
    by_status = { hash_key = "status", range_key = "sk", projection_type = "KEYS_ONLY" }
  }

  ttl    = { attribute_name = "expires_at" }
  stream = { view_type = "NEW_AND_OLD_IMAGES" }

  tags = { Environment = "prod", Owner = "orders" }
}
```

This creates the on-demand table `orders` with a composite key, one global secondary index, TTL on `expires_at`, a stream of new and old images, point-in-time recovery, deletion protection, and encryption with the AWS owned key. `module.orders.stream_arn` is ready to wire into a Lambda event source mapping.

## Architecture

```text
root (one table)
├── aws_dynamodb_table.this | .autoscaled      the table; the second variant ignores capacity drift
├── modules/autoscaling                       scalable target and target-tracking policy per scaled dimension
├── aws_dynamodb_resource_policy.this         optional, rendered from resource_policy_statements
├── aws_dynamodb_contributor_insights.this    optional, table-level
├── aws_dynamodb_contributor_insights.index   optional, one per named GSI
└── aws_dynamodb_kinesis_streaming_destination.this   optional
```

Inputs are validated at the variable level where one variable is enough and by preconditions on the table where two interact. The autoscaling submodule receives the table name and the scaled dimensions and registers one scalable target and one target-tracking policy per dimension. Helper resources reference the table by name or ARN, so they are created after it and destroyed before it.

| Concern | Default | Declare |
| --- | --- | --- |
| Throughput | `PAY_PER_REQUEST`; optional `on_demand_throughput` caps on the table and per GSI. | `billing_mode = "PROVISIONED"` with `read_capacity`, `write_capacity`, and per-GSI capacities, or an `autoscaling` object that covers each dimension. |
| Autoscaling | None. `autoscaling` defaults to `null`. | `autoscaling = { table = { read = { min_capacity, max_capacity } ... }, indexes = { <gsi> = { ... } } }`. Unset capacities start at the dimension minimum. `modules/autoscaling` is also usable standalone against a table the root did not create. |
| Encryption key | AWS owned key. | `server_side_encryption = { kms_key_arn = "<arn>" }`; each replica names its own regional key. |
| Indexes | None. | `global_secondary_indexes` and `local_secondary_indexes` keyed by index name; key attributes declared in `attributes`. |
| Streams and replicas | None. | `stream = { view_type }`; `replicas` keyed by region need `NEW_AND_OLD_IMAGES` and on-demand billing or autoscaling. |
| Access policy | None. | `resource_policy_statements` keyed by Sid; `resources` defaults to the table and every index; the JSON is sorted and null-free. |
| Observability | None. | `contributor_insights_enabled`, `contributor_insights_indexes`, `kinesis_stream_arn` with `kinesis_approximate_creation_date_time_precision`. |

## Usage patterns

| Example | What it shows |
| --- | --- |
| [`examples/minimal`](examples/minimal) | The smallest working table: a composite key, everything else defaulted. |
| [`examples/complete`](examples/complete) | The full on-demand interface: GSIs with per-index caps, an LSI, TTL, a stream, a customer managed key, a recovery window, Contributor Insights, a Kinesis destination, a resource policy with an Allow and a conditioned Deny, timeouts. |
| [`examples/provisioned-autoscaled`](examples/provisioned-autoscaled) | A PROVISIONED table and its GSI scaled by Application Auto Scaling, with explicit initial capacities. |
| [`examples/global-table`](examples/global-table) | Replicas in two regions with a customer managed key per region. |
| [`examples/multiple-tables`](examples/multiple-tables) | `for_each` over a map of tables: one module call per table sharing a naming convention and tags. |

## Security model

Encryption

- `server_side_encryption.enabled` is always `true` and is not an input. With `kms_key_arn` unset the table uses the AWS owned key; with it set, the named customer managed key, whose key policy must allow DynamoDB to use it. The ARN must be a full key ARN, not an alias, so cross-account keys and rotation are unambiguous.
- When the table uses a customer managed key, every replica must name its own regional key. A precondition rejects a replica without one, so the encryption posture is the same in every region.

Recovery and deletion

- Point-in-time recovery is on by default (`point_in_time_recovery.enabled`), with `recovery_period_in_days` (1 to 35) to shorten the window; replicas inherit the setting unless overridden per region.
- Deletion protection is on by default (`deletion_protection_enabled`); replicas inherit it unless overridden per region. `terraform destroy` fails until it is applied as `false` first.
- Two `check` blocks, `deletion_protection_disabled` and `point_in_time_recovery_disabled`, warn on every plan and apply while either is off. They never block.

Access

- No resource-based policy exists unless `resource_policy_statements` is non-empty. Each statement is keyed by an alphanumeric Sid, defaults to `Allow`, needs at least one principal and one action, and defaults `resources` to the table ARN and `<table arn>/index/*`.
- A statement with a wildcard principal (`"*"`) must carry at least one condition. Principal types are `AWS`, `Service`, `Federated`, or `CanonicalUser`.
- The rendered document sorts statements by Sid and sorts principals, actions, resources, and condition values, and omits empty keys, so a policy diff is a real change.
- The module grants nothing to anyone: IAM policies for readers and writers, Lambda event source permissions, and Kinesis stream policies are declared by their owners against the module's outputs.

Not created here

- KMS keys, Kinesis Data Streams, IAM roles and policies for table consumers, CloudWatch alarms, AWS Backup plans, DAX clusters, and Lambda event source mappings. They have separate lifecycles and owners; the module consumes their identifiers and exposes its own.

## Lifecycle notes

- Declaring `autoscaling` selects `aws_dynamodb_table.autoscaled[0]`, which sets `ignore_changes = [read_capacity, write_capacity, global_secondary_index]` so the values Application Auto Scaling writes never show as drift. Terraform cannot make `ignore_changes` conditional, so two identical resource blocks exist and exactly one is created; outputs resolve from whichever exists, and `scripts/check-resource-variants.sh` (`make variants`, pre-commit) fails when the bodies drift apart. Toggling `autoscaling` between `null` and an object changes the resource address: add a `moved` block from `aws_dynamodb_table.this[0]` to `aws_dynamodb_table.autoscaled[0]` (or back) so the table is not replaced.
- `global_secondary_index` is a set, so its capacities cannot be ignored individually and the whole block is ignored on the autoscaled variant. To add, remove, or reshape an index on an autoscaled table, apply the index change through the AWS API or CLI first and then update the configuration to match, or temporarily move the table to the `this` variant (with a `moved` block), apply the index change, and move it back.
- An explicit `read_capacity`, `write_capacity`, or GSI capacity on an autoscaled dimension is its initial value and must lie within the dimension's bounds; without one the dimension starts at `min_capacity`.
- The attribute contract is checked before every plan: an attribute that no key uses, or a key attribute that is not declared, fails the plan with the attribute named. TTL attributes are not key attributes and are not declared in `attributes`.
- `ttl.enabled = false` keeps the attribute name in configuration and renders the block disabled without a name, as the provider requires; `ttl = null` leaves TTL unmanaged.
- Replicas are created and deleted one region at a time by the provider, which can take several minutes each; `timeouts` passes through the table's create, update, and delete timeouts.
- Changing `name`, `hash_key`, `range_key`, or an attribute's type replaces the table. Changing a GSI's keys or projection replaces that index.
- The AWS provider marks `hash_key` and `range_key` as deprecated in favour of `key_schema` from 6.3x onwards and prints a warning on every plan. The module keeps the classic attributes on purpose (see Compatibility and scope); the warning is expected and harmless.

## Testing

Two layers, deliberately separate:

- **Contract tests** (`tests/`, run by `make test` and by CI) use `mock_provider`: no credentials, nothing created, placeholder identifiers such as the AWS documentation account `123456789012`. They pin the module's interface, validations, rendered JSON, variant selection, and defaults, and run identically for everyone.
- **Integration suites** (`tests/integration/`, run by `make integration-smoke` and `make integration-provisioned-autoscaled`, or the dispatch-only `integration` workflow) apply the module for real in **your** account with **your** credentials and region from the environment, against a disposable fixture the suite creates and destroys itself. `smoke` proves an on-demand table with a GSI, TTL, point-in-time recovery, a stream, and a resource policy is accepted by the AWS APIs; `provisioned-autoscaled` proves a provisioned table and its GSI register with Application Auto Scaling. See [tests/integration/README.md](tests/integration/README.md) for permissions and the GitHub environment contract.

## Design principles

- Single responsibility. `modules/autoscaling` has one reason to change: the shape of Application Auto Scaling for DynamoDB dimensions. The root owns the table and its directly attached helpers (resource policy, Contributor Insights, Kinesis destination).
- Open/closed. New behaviour is added by declaring data (an index, a replica region, a policy statement, a scaled dimension), not by editing the module. Timeouts, tags, table class, on-demand caps, and the recovery window are inputs.
- Liskov substitution. Whether autoscaling is on or off, the caller sees the same outputs: `local.table` resolves from whichever table variant exists. A table on a customer managed key is a drop-in for one on the AWS owned key.
- Interface segregation. Feature groups are optional objects that default to `null` or `{}`. A minimal table needs `name`, `hash_key`, and `attributes`.
- Dependency inversion. The root depends on identifiers (KMS key ARNs, Kinesis stream ARNs, principal ARNs), never on how they were produced. There are no data sources; the table ARN flows into the helper resources from the table resource itself.

The full rationale, including why the v0.1.x design was replaced, is in [docs/DESIGN.md](docs/DESIGN.md).

## Compatibility and scope

- Terraform `>= 1.7.0, < 2.0.0`. AWS provider `>= 6.35.0, < 7.0.0`.
- Index keys are rendered with the classic `hash_key` and `range_key` attributes. Providers from 6.3x onwards print a deprecation warning in favour of the `key_schema` block, but removing an index through `key_schema` deleted every index before provider 6.36.0 ([#46602](https://github.com/hashicorp/terraform-provider-aws/issues/46602)). The module switches to `key_schema`, and gains multi-attribute index keys, in a minor release once its provider floor passes that fix.
- Not in v1: `import_table`, restoring from a backup or a point in time, `warm_throughput`, `global_table_witness`, the Contributor Insights `mode`, and a table variant that autoscales without ignoring `global_secondary_index`. They are roadmap items and will be added as optional inputs without breaking this interface.

## Versioning and releases

Releases follow semantic versioning: incompatible interface changes bump the major version, new optional inputs and outputs bump the minor version, fixes bump the patch version. Every release is a signed annotated tag `vX.Y.Z`.

Pin the full commit SHA of the release tag and record the tag in a comment, so the source cannot move under you:

```hcl
module "orders" {
  source = "git::https://github.com/hatan4ik/aws.modules.dynamodb.git?ref=<commit-sha>" # v1.0.0
}

module "orders_autoscaling" {
  source = "git::https://github.com/hatan4ik/aws.modules.dynamodb.git//modules/autoscaling?ref=<commit-sha>" # v1.0.0
}
```

The `module-release` workflow publishes an immutable GitHub release only from a GitHub-verified, signed, annotated semantic-version tag that points at the merged `main` revision; lightweight or unsigned tags are rejected before anything is published. With a GitHub-associated GPG or SSH signing key configured:

```bash
git fetch origin
git tag -s vX.Y.Z <commit> -m "vX.Y.Z"
git push origin vX.Y.Z
gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z
```

Dispatch from the tag, never from `main`: the workflow verifies that the tag points at the revision it checked out, and a maintenance release for an older line (for example a 0.1.x fix after 1.0.0 landed on `main`) is cut from that line's commit.

Upgrading from 0.1.x: read [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md) for the input mapping, the settings that preserve the existing table, and ready-to-paste `moved` blocks. All changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Contributing

Development setup, the local quality gate, the test-first workflow, and the release process are described in [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).

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

| Name | Source | Version |
|------|--------|---------|
| <a name="module_autoscaling"></a> [autoscaling](#module\_autoscaling) | ./modules/autoscaling | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_dynamodb_contributor_insights.index](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_contributor_insights) | resource |
| [aws_dynamodb_contributor_insights.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_contributor_insights) | resource |
| [aws_dynamodb_kinesis_streaming_destination.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_kinesis_streaming_destination) | resource |
| [aws_dynamodb_resource_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_resource_policy) | resource |
| [aws_dynamodb_table.autoscaled](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_dynamodb_table.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_attributes"></a> [attributes](#input\_attributes) | Attribute definitions keyed by attribute name with the DynamoDB type S, N, or B as the value. Declare exactly the attributes used by the primary key and by index keys: DynamoDB rejects unused definitions and undeclared key attributes, and the module enforces both at plan time. | `map(string)` | n/a | yes |
| <a name="input_autoscaling"></a> [autoscaling](#input\_autoscaling) | Application Auto Scaling for a PROVISIONED table. Null disables it. table.read, table.write, and each indexes.<gsi>.read or .write is a dimension with min\_capacity, max\_capacity, target\_utilization (percent, default 70), scale\_in\_cooldown (default 300), and scale\_out\_cooldown (default 60). When set, the table ignores later capacity drift and unset capacities start at the dimension minimum. See modules/autoscaling. | <pre>object({<br/>    table = optional(object({<br/>      read = optional(object({<br/>        min_capacity       = number<br/>        max_capacity       = number<br/>        target_utilization = optional(number, 70)<br/>        scale_in_cooldown  = optional(number, 300)<br/>        scale_out_cooldown = optional(number, 60)<br/>      }))<br/>      write = optional(object({<br/>        min_capacity       = number<br/>        max_capacity       = number<br/>        target_utilization = optional(number, 70)<br/>        scale_in_cooldown  = optional(number, 300)<br/>        scale_out_cooldown = optional(number, 60)<br/>      }))<br/>    }))<br/>    indexes = optional(map(object({<br/>      read = optional(object({<br/>        min_capacity       = number<br/>        max_capacity       = number<br/>        target_utilization = optional(number, 70)<br/>        scale_in_cooldown  = optional(number, 300)<br/>        scale_out_cooldown = optional(number, 60)<br/>      }))<br/>      write = optional(object({<br/>        min_capacity       = number<br/>        max_capacity       = number<br/>        target_utilization = optional(number, 70)<br/>        scale_in_cooldown  = optional(number, 300)<br/>        scale_out_cooldown = optional(number, 60)<br/>      }))<br/>    })), {})<br/>  })</pre> | `null` | no |
| <a name="input_billing_mode"></a> [billing\_mode](#input\_billing\_mode) | PAY\_PER\_REQUEST (on-demand) or PROVISIONED. Provisioned tables need read\_capacity and write\_capacity on the table and every GSI, or an autoscaling dimension covering each. | `string` | `"PAY_PER_REQUEST"` | no |
| <a name="input_contributor_insights_enabled"></a> [contributor\_insights\_enabled](#input\_contributor\_insights\_enabled) | Enable CloudWatch Contributor Insights on the table. | `bool` | `false` | no |
| <a name="input_contributor_insights_indexes"></a> [contributor\_insights\_indexes](#input\_contributor\_insights\_indexes) | Global secondary index names to enable CloudWatch Contributor Insights on. Each must be a key of global\_secondary\_indexes. | `set(string)` | `[]` | no |
| <a name="input_deletion_protection_enabled"></a> [deletion\_protection\_enabled](#input\_deletion\_protection\_enabled) | Refuse to delete the table until this is set to false. On by default; the deletion\_protection\_disabled check warns while it is off. | `bool` | `true` | no |
| <a name="input_global_secondary_indexes"></a> [global\_secondary\_indexes](#input\_global\_secondary\_indexes) | Global secondary indexes keyed by index name. projection\_type is ALL, KEYS\_ONLY, or INCLUDE (which requires non\_key\_attributes). Key attributes must be declared in attributes. read\_capacity and write\_capacity apply to PROVISIONED tables; on\_demand\_throughput to PAY\_PER\_REQUEST tables. | <pre>map(object({<br/>    hash_key           = string<br/>    range_key          = optional(string)<br/>    projection_type    = string<br/>    non_key_attributes = optional(set(string))<br/>    read_capacity      = optional(number)<br/>    write_capacity     = optional(number)<br/>    on_demand_throughput = optional(object({<br/>      max_read_request_units  = optional(number)<br/>      max_write_request_units = optional(number)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_hash_key"></a> [hash\_key](#input\_hash\_key) | Partition key attribute name. Must be declared in attributes. | `string` | n/a | yes |
| <a name="input_kinesis_approximate_creation_date_time_precision"></a> [kinesis\_approximate\_creation\_date\_time\_precision](#input\_kinesis\_approximate\_creation\_date\_time\_precision) | Precision of the ApproximateCreationDateTime written to the Kinesis stream: MILLISECOND or MICROSECOND. | `string` | `"MILLISECOND"` | no |
| <a name="input_kinesis_stream_arn"></a> [kinesis\_stream\_arn](#input\_kinesis\_stream\_arn) | Kinesis Data Stream that receives item-level changes. Null creates no destination. | `string` | `null` | no |
| <a name="input_local_secondary_indexes"></a> [local\_secondary\_indexes](#input\_local\_secondary\_indexes) | Local secondary indexes keyed by index name, at most five. Each shares the table hash\_key and names its own range\_key, which must be declared in attributes; the table needs a range\_key. projection\_type follows the GSI rules. | <pre>map(object({<br/>    range_key          = string<br/>    projection_type    = string<br/>    non_key_attributes = optional(set(string))<br/>  }))</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Table name: 3-255 characters of letters, digits, underscores, hyphens, or dots. Also the Name tag and the prefix of autoscaling policy names. | `string` | n/a | yes |
| <a name="input_on_demand_throughput"></a> [on\_demand\_throughput](#input\_on\_demand\_throughput) | Maximum read and write request units per second of an on-demand table. Each limit is at least 1, or -1 to remove a limit set earlier. Only valid with PAY\_PER\_REQUEST. | <pre>object({<br/>    max_read_request_units  = optional(number)<br/>    max_write_request_units = optional(number)<br/>  })</pre> | `null` | no |
| <a name="input_point_in_time_recovery"></a> [point\_in\_time\_recovery](#input\_point\_in\_time\_recovery) | Point-in-time recovery, enabled by default. recovery\_period\_in\_days (1-35) shortens the AWS default window and is only valid while enabled. | <pre>object({<br/>    enabled                 = optional(bool, true)<br/>    recovery_period_in_days = optional(number)<br/>  })</pre> | <pre>{<br/>  "enabled": true<br/>}</pre> | no |
| <a name="input_range_key"></a> [range\_key](#input\_range\_key) | Sort key attribute name, or null for a partition-key-only table. Must be declared in attributes and differ from hash\_key. | `string` | `null` | no |
| <a name="input_read_capacity"></a> [read\_capacity](#input\_read\_capacity) | Provisioned read capacity units of the table. Required with PROVISIONED unless autoscaling.table.read is set, in which case it is the initial value and must lie within the bounds; forbidden with PAY\_PER\_REQUEST. | `number` | `null` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Global table replicas keyed by region name. kms\_key\_arn is the replica's regional customer managed key (required when the table uses one); point\_in\_time\_recovery and deletion\_protection\_enabled default to the table's settings; propagate\_tags defaults to true; consistency\_mode is EVENTUAL or STRONG. Replicas need stream.view\_type = NEW\_AND\_OLD\_IMAGES and PAY\_PER\_REQUEST or autoscaling. | <pre>map(object({<br/>    kms_key_arn                 = optional(string)<br/>    point_in_time_recovery      = optional(bool)<br/>    propagate_tags              = optional(bool, true)<br/>    deletion_protection_enabled = optional(bool)<br/>    consistency_mode            = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_resource_policy_statements"></a> [resource\_policy\_statements](#input\_resource\_policy\_statements) | Resource-based policy statements keyed by alphanumeric Sid. principals maps a type (AWS, Service, Federated, CanonicalUser) to identifiers; a wildcard principal requires a condition. resources defaults to the table and every index. The rendered document is sorted and null-free; an empty map creates no policy. | <pre>map(object({<br/>    effect     = optional(string, "Allow")<br/>    principals = map(set(string))<br/>    actions    = set(string)<br/>    resources  = optional(set(string))<br/>    conditions = optional(list(object({<br/>      test     = string<br/>      variable = string<br/>      values   = set(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_server_side_encryption"></a> [server\_side\_encryption](#input\_server\_side\_encryption) | Encryption at rest is always enabled. kms\_key\_arn selects a customer managed KMS key; null uses the AWS owned key. Replicas of a table on a customer managed key must each name their own regional key. | <pre>object({<br/>    kms_key_arn = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_stream"></a> [stream](#input\_stream) | DynamoDB Streams. Null disables the stream. view\_type is KEYS\_ONLY, NEW\_IMAGE, OLD\_IMAGE, or NEW\_AND\_OLD\_IMAGES; replicas require NEW\_AND\_OLD\_IMAGES. | <pre>object({<br/>    view_type = string<br/>  })</pre> | `null` | no |
| <a name="input_table_class"></a> [table\_class](#input\_table\_class) | Storage class of the table: STANDARD or STANDARD\_INFREQUENT\_ACCESS. | `string` | `"STANDARD"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the table, propagated to replicas by default, and applied to autoscaling targets. The module adds a Name tag and never overrides caller tags. | `map(string)` | `{}` | no |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | Create, update, and delete timeouts for the table, as duration strings. | <pre>object({<br/>    create = optional(string)<br/>    update = optional(string)<br/>    delete = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_ttl"></a> [ttl](#input\_ttl) | Time to live on the named Number attribute holding an epoch-seconds expiry. Null leaves TTL unmanaged. enabled = false keeps the declaration while TTL is off; the attribute must not be a key attribute. | <pre>object({<br/>    attribute_name = string<br/>    enabled        = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_write_capacity"></a> [write\_capacity](#input\_write\_capacity) | Provisioned write capacity units of the table. Required with PROVISIONED unless autoscaling.table.write is set, in which case it is the initial value and must lie within the bounds; forbidden with PAY\_PER\_REQUEST. | `number` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_arn"></a> [arn](#output\_arn) | Table ARN. |
| <a name="output_autoscaling_policy_arns"></a> [autoscaling\_policy\_arns](#output\_autoscaling\_policy\_arns) | Target-tracking policy ARNs keyed by dimension; empty when autoscaling is disabled. |
| <a name="output_autoscaling_target_resource_ids"></a> [autoscaling\_target\_resource\_ids](#output\_autoscaling\_target\_resource\_ids) | Application Auto Scaling resource IDs keyed by dimension (table\_read, table\_write, index\_<name>\_read, index\_<name>\_write); empty when autoscaling is disabled. |
| <a name="output_billing_mode"></a> [billing\_mode](#output\_billing\_mode) | Billing mode of the table. |
| <a name="output_global_secondary_index_arns"></a> [global\_secondary\_index\_arns](#output\_global\_secondary\_index\_arns) | Global secondary index ARNs keyed by index name (<table arn>/index/<name>). |
| <a name="output_hash_key"></a> [hash\_key](#output\_hash\_key) | Partition key attribute name. |
| <a name="output_id"></a> [id](#output\_id) | Table ID (the table name). |
| <a name="output_local_secondary_index_arns"></a> [local\_secondary\_index\_arns](#output\_local\_secondary\_index\_arns) | Local secondary index ARNs keyed by index name (<table arn>/index/<name>). |
| <a name="output_name"></a> [name](#output\_name) | Table name. |
| <a name="output_range_key"></a> [range\_key](#output\_range\_key) | Sort key attribute name, or null. |
| <a name="output_replica_arns"></a> [replica\_arns](#output\_replica\_arns) | Replica table ARNs keyed by region; empty when no replicas are declared. |
| <a name="output_resource_policy"></a> [resource\_policy](#output\_resource\_policy) | Rendered resource-based policy JSON, or null when no statements are declared. |
| <a name="output_stream_arn"></a> [stream\_arn](#output\_stream\_arn) | ARN of the DynamoDB stream, or null when stream is not declared. |
| <a name="output_stream_label"></a> [stream\_label](#output\_stream\_label) | Timestamp label of the DynamoDB stream, or null when stream is not declared. |
| <a name="output_table_class"></a> [table\_class](#output\_table\_class) | Storage class of the table. |
<!-- END_TF_DOCS -->
