# Design: aws.modules.dynamodb v1

Status: accepted 2026-09-23. Supersedes the v0.1.x "typed table" design.

## Purpose

`aws.modules.dynamodb` provisions **one** Amazon DynamoDB table together with
the settings and helper resources a production table needs: key schema and
attribute definitions, global and local secondary indexes, on-demand or
provisioned throughput with Application Auto Scaling, DynamoDB Streams,
multi-region replicas, TTL, point-in-time recovery, server-side encryption,
a resource-based policy, CloudWatch Contributor Insights, and a Kinesis Data
Streams destination. It is secure by default, explicit by declaration, and
composable: every helper resource is optional and every external dependency is
an identifier the caller passes in.

The module deliberately does **not** create KMS keys, Kinesis streams, IAM
roles or policies for table consumers, alarms, backup plans, or DAX clusters.
Those are separate concerns with separate lifecycles and owners. The module
consumes their identifiers and exposes its own.

## Why the v0.1.x design was replaced

| v0.1.x behaviour | Problem | v1 decision |
|---|---|---|
| `attributes = { name = { type = "S" } }` accepted attributes that no key used. | The DynamoDB API rejects unused attribute definitions, so a wrong map failed at apply time, not plan time. | `attributes = { name = "S" }` (map of string). A precondition requires every declared attribute to be used by a key and every key attribute to be declared. |
| No local secondary indexes. | Tables that need alternative sort keys within a partition could not be expressed. | `local_secondary_indexes` map with the same projection rules as GSIs; a precondition requires the table `range_key`. |
| No streams, table class, replicas, on-demand limits, resource policy, contributor insights, or Kinesis destination. | Event-driven, global, cost-tuned, and cross-account tables needed resources outside the module, each with its own lifecycle bugs. | Typed optional inputs: `stream`, `table_class`, `replicas`, `on_demand_throughput`, `resource_policy_statements`, `contributor_insights_*`, `kinesis_stream_arn`. Each renders to exactly one resource or block. |
| Provisioned tables had fixed capacity. | No Application Auto Scaling; either over-provisioned or throttled. | `autoscaling` object rendered by `modules/autoscaling`; a second table resource ignores capacity drift so Terraform and the scaler do not fight. |
| Cross-variable rules lived on a `terraform_data.input_contract` resource. | A phantom resource in state whose only job was to fail; `terraform_data` needs the `terraform` provider. | Preconditions live on the table resource itself. |
| `ttl_attribute_name`, `kms_key_arn`, `point_in_time_recovery_enabled` were flat scalars. | Each feature had a different shape and no room to grow (`recovery_period_in_days`, `enabled` toggle on TTL). | Feature groups are objects: `ttl`, `server_side_encryption`, `point_in_time_recovery`. |
| No tests, no examples. | Regressions and misuse were found at apply time. | `terraform test` with `mock_provider` covers every default, validation, and feature group; five executable examples. |
| The module could not name the offending index in an error. | Index maps were validated only by the API. | Every validation and precondition names the index, attribute, or dimension it rejects. |

## Principles and how the module applies them

- **Single responsibility.** `modules/autoscaling` has one reason to change:
  the shape of Application Auto Scaling for DynamoDB dimensions. The root
  owns the table and its directly attached helpers (resource policy,
  contributor insights, Kinesis destination).
- **Open/closed.** New behaviour is added by declaring data (an index, a
  replica region, a policy statement, a scaled dimension), not by editing the
  module. Timeouts, tags, and every AWS default that can be overridden are
  inputs.
- **Liskov substitution.** Whether autoscaling is on or off, the caller sees
  the same outputs: `local.table` resolves from whichever table variant exists.
  A table with a caller-supplied KMS key is a drop-in for one on the AWS
  owned key.
- **Interface segregation.** Feature groups are optional objects that default
  to `null` or `{}`. A minimal table needs `name`, `hash_key`, and
  `attributes`.
- **Dependency inversion.** The root depends on identifiers (KMS key ARNs,
  Kinesis stream ARNs, principal ARNs), never on how they were produced. There
  are no data sources; the table ARN flows into the helper resources from the
  table resource itself.
- **Clean, deterministic code.** Sorted statement, action, and principal lists
  in the rendered policy, null stripping in rendered JSON, and validations
  that fail at plan time with actionable messages.

## Architecture

```text
root (one table)
├── aws_dynamodb_table.this | .autoscaled     the table; the second variant ignores capacity drift
├── modules/autoscaling                      targets and target-tracking policies per scaled dimension
├── aws_dynamodb_resource_policy.this        optional, rendered from resource_policy_statements
├── aws_dynamodb_contributor_insights.this   optional, table-level
├── aws_dynamodb_contributor_insights.index  optional, one per named GSI
└── aws_dynamodb_kinesis_streaming_destination.this   optional
```

Data flow: inputs are validated at the variable level where one variable is
enough and by preconditions on the table where two variables interact
(key attributes against `attributes`, capacities against `billing_mode` and
`autoscaling`, replicas against `stream` and `server_side_encryption`). The
autoscaling submodule receives the table name and the scaled dimensions and
registers one scalable target and one target-tracking policy per dimension.
Helper resources reference the table by name or ARN, so they are created
after it and destroyed before it.

### Two table variants

Terraform cannot make `lifecycle.ignore_changes` conditional, so the table is
declared twice with identical bodies:

- `aws_dynamodb_table.this[0]` is created when `autoscaling` is `null`.
- `aws_dynamodb_table.autoscaled[0]` is created when `autoscaling` is set. It
  adds `ignore_changes = [read_capacity, write_capacity, global_secondary_index]`
  so the capacity values Application Auto Scaling writes do not show as drift.
  `global_secondary_index` is a set, so per-attribute ignores inside it are not
  possible; the whole block is ignored, which means index changes on an
  autoscaled table are applied outside Terraform or by temporarily moving the
  table to the `this` variant.

The initial capacity of an autoscaled dimension is its explicit
`read_capacity`/`write_capacity` when given, otherwise the dimension's
`min_capacity`; the scaler owns the value from then on.

`scripts/check-resource-variants.sh` fails `make check` and the pre-commit
hook when the two bodies drift apart in anything other than `count` and
`ignore_changes`. Toggling `autoscaling` between `null` and an object changes
the resource address; `docs/UPGRADE-1.0.md` gives the `moved` block.

### Root interface (summary)

Required: `name`, `hash_key`, `attributes`.

Optional groups (all default to a safe value):

- Keys and indexes: `range_key`, `global_secondary_indexes`,
  `local_secondary_indexes`.
- Throughput: `billing_mode` (`PAY_PER_REQUEST`), `read_capacity`,
  `write_capacity`, `on_demand_throughput`, `autoscaling`, `table_class`
  (`STANDARD`).
- Data protection: `server_side_encryption` (always on; `kms_key_arn`
  selects a customer managed key), `point_in_time_recovery` (on),
  `deletion_protection_enabled` (true), `ttl`.
- Integration: `stream`, `replicas`, `kinesis_stream_arn` and
  `kinesis_approximate_creation_date_time_precision` (`MILLISECOND`),
  `resource_policy_statements`, `contributor_insights_enabled`,
  `contributor_insights_indexes`.
- `timeouts`, `tags`.

Outputs expose every identifier a caller needs to wire IAM, event sources, or
further modules: `id`, `name`, `arn`, `stream_arn`, `stream_label`,
`hash_key`, `range_key`, `billing_mode`, `table_class`,
`global_secondary_index_arns`, `local_secondary_index_arns`, `replica_arns`,
`autoscaling_target_resource_ids`, `autoscaling_policy_arns`, and
`resource_policy`.

### Validation rules

Variable-level (one variable is enough):

- `name` is 3 to 255 characters of `[a-zA-Z0-9_.-]`; index names follow the
  same rule.
- `attributes` values are `S`, `N`, or `B`; keys are 1 to 255 characters.
- `billing_mode`, `table_class`, `stream.view_type`, projection types, replica
  `consistency_mode`, and the Kinesis precision are enumerated.
- `read_capacity`, `write_capacity`, and index capacities are at least 1;
  on-demand limits are at least 1 or `-1` (remove the limit).
- An `INCLUDE` projection requires `non_key_attributes`; `ALL` and
  `KEYS_ONLY` forbid them. An index `hash_key` differs from its `range_key`.
- At most five local secondary indexes.
- `point_in_time_recovery.recovery_period_in_days` is 1 to 35 and only set
  while recovery is enabled.
- `server_side_encryption.kms_key_arn`, replica `kms_key_arn`, and
  `kinesis_stream_arn` are full ARNs of the right service.
- `replicas` keys are region names.
- `resource_policy_statements` keys are alphanumeric Sids; `effect` is
  `Allow` or `Deny`; principal types are `AWS`, `Service`, `Federated`, or
  `CanonicalUser`; a wildcard principal requires a condition; `actions` and
  `principals` are non-empty.
- `autoscaling` scales at least one dimension; each dimension has
  `1 <= min_capacity <= max_capacity`, `target_utilization` 20 to 90, and
  non-negative cooldowns.

Preconditions on the table (two variables interact):

- Every attribute used by the primary key, a GSI key, or an LSI key is
  declared in `attributes`, and every declared attribute is used by some key.
- `hash_key` differs from `range_key`.
- GSI and LSI names do not collide.
- `local_secondary_indexes` requires `range_key`.
- `ttl.attribute_name` is not a key attribute.
- `PROVISIONED` requires `read_capacity` and `write_capacity` on the table and
  on every GSI unless `autoscaling` covers that dimension; an explicit capacity
  must lie within the autoscaling bounds of its dimension.
- `PAY_PER_REQUEST` forbids capacities and `autoscaling`; `on_demand_throughput`
  (table or GSI) requires `PAY_PER_REQUEST`.
- `autoscaling.indexes` and `contributor_insights_indexes` name declared GSIs.
- `replicas` requires `stream.view_type = "NEW_AND_OLD_IMAGES"` and either
  `PAY_PER_REQUEST` or `autoscaling`.
- When the table uses a customer managed key, every replica names its own
  regional key, so the encryption posture is the same in every region.

### Lifecycle rules

- Server-side encryption is always enabled. With `kms_key_arn` unset the table
  uses the AWS owned key; with it set, the named customer managed key.
  Replicas take their own regional key.
- `ttl.enabled = false` keeps the declared attribute name in configuration
  but renders the block disabled without a name, as the provider requires.
- Replicas inherit the table's deletion protection and point-in-time recovery
  settings unless overridden per region, and propagate tags by default.
- Two `check` blocks warn without blocking: `deletion_protection_disabled` and
  `point_in_time_recovery_disabled`.
- Timeouts are passed through unchanged.

## Security defaults

- Encryption at rest is on and cannot be turned off; the caller chooses the
  key. Point-in-time recovery is on. Deletion protection is on.
- No resource policy unless statements are declared; a wildcard principal
  needs a condition; rendered JSON is sorted and null-free so policy diffs are
  meaningful.
- Replicas inherit the table's deletion protection and point-in-time recovery
  settings unless overridden per region, and propagate tags by default.
- The module adds only a `Name` tag and never overrides caller tags.

## Testing strategy

- Contract tests use `mock_provider` with `command = plan`; no credentials.
  Computed attributes (ARNs, stream labels) are unknown at plan time, so
  assertions target configured attributes and maps of known length. One run
  uses `command = apply` with a `mock_resource` default ARN to assert the
  resource policy's default `Resource` list, which is derived from the table
  ARN.
- Root `tests/` cover: secure defaults, every validation and precondition via
  `expect_failures`, every feature group (indexes, streams, replicas, resource
  policy JSON, contributor insights, Kinesis), autoscaling variant selection,
  and the `check` blocks.
- `modules/autoscaling` has its own `tests/` and is exercised in CI on its
  own.
- Every example is initialised and validated in CI; examples are the
  documentation's executable form.
- Static policy: `tflint` with the AWS ruleset, Checkov, Trivy; generated
  docs are checked for drift; the two table variants are diffed.

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0` (the consuming platform pins 1.7.5).
- AWS provider `>= 6.35.0, < 7.0.0`.
- Global secondary index keys are rendered with the classic `hash_key` and
  `range_key` attributes. Providers from 6.3x onwards print a deprecation
  warning in favour of the `key_schema` block, but removing an index through
  `key_schema` deleted every index before provider 6.36.0 (#46602). The
  module switches to `key_schema`, and gains multi-attribute index keys, in a
  minor release once its provider floor passes that fix.
- Not in v1: `import_table`, `restore_*` from backups, `warm_throughput`,
  `global_table_witness`, Contributor Insights `mode`, and a table variant
  that autoscales without ignoring `global_secondary_index`. They are roadmap
  items and will be added as optional inputs without breaking this interface.

## Migration

`docs/UPGRADE-1.0.md` maps every v0.1.x input to its v1 equivalent, lists the
inputs that keep the table name and key schema unchanged, and gives `moved`
blocks so a consumer adopts v1 without replacing the table.
