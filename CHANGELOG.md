# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

Correctness release. Every change below makes configuration that was already wrong fail at plan time, or behave as documented. Some configurations that passed plan on 1.0.0 now fail plan, and some tables see an in-place tag change; check **Upgrade notes**. Proposed version: 1.1.0. The tag contract fix alone would be a patch, but autoscaled global tables now use a new resource address (`aws_dynamodb_table_replica.this`).

### Fixed

- **Provisioned global tables could never be created.** DynamoDB rejects a replica of a `PROVISIONED` table unless write capacity on the table and on every GSI is autoscaled ("write capacity should either be Pay-Per-Request or AutoScaled").
  - The plan-time rule was too weak: it only required `autoscaling != null`. A table with `autoscaling = { table = { read = ... } }` and no write dimension, or a GSI without a write dimension, passed plan and failed at apply. A precondition now requires an `autoscaling` write dimension for the table and for every GSI whenever a `PROVISIONED` table has replicas, and names each table or index without one.
  - Even a correct configuration failed on its first apply. The provider creates inline `replica` blocks inside the table's own create call, before `module.autoscaling` can register the scalable targets, which need the table to exist first. No `depends_on` can fix that order. Replicas of an autoscaled table are now separate `aws_dynamodb_table_replica.this["<region>"]` resources with `depends_on = [module.autoscaling]`. The `autoscaled` table variant renders no inline replicas and ignores `replica`. On-demand global tables are unchanged.
- **A caller's `Name` tag was silently overwritten** with the table name: `merge(var.tags, { Name = var.name })` let the module win. This contradicted the documented contract ("never overrides caller tags"). Both table variants now use `merge({ Name = var.name }, var.tags)`, the pattern `aws.modules.s3` and `aws.modules.ksm` use. **Behavior change:** a caller who sets `tags.Name` will see the table's (and propagated replicas') `Name` tag change in place from the table name to their value on the next apply.
- **Replica encryption symmetry was enforced in one direction only.** A table on the AWS owned key with a replica naming a customer managed key passed plan, giving a different encryption posture per region. The precondition now rejects that mismatch too and names the regions. **Behavior change:** such configurations, including ones already applied, now fail plan. Either give the table a customer managed key, or remove `kms_key_arn` from the replicas.

### Added

- Precondition on `aws_dynamodb_resource_policy.this`: the rendered document must fit DynamoDB's 20 KB resource-based policy limit. The size is estimated at plan time with the longest possible table ARN, so it never under-counts.
- Advisory `check "autoscaled_index_drift"`: warns when `global_secondary_indexes` no longer matches the indexes on an existing autoscaled table. That variant ignores `global_secondary_index`, so a newly declared index never reaches the table, while its `autoscaling.indexes` targets and `contributor_insights_indexes` entries fail at apply.
- Precondition rejecting `consistency_mode = "STRONG"` on an autoscaled table. Multi-Region strong consistency needs every replica in one request, which separate replica resources cannot make.
- `variants` job in the `terraform-quality` workflow that runs `scripts/check-resource-variants.sh` on every pull request. Until now it ran only through `make check` and pre-commit.
- Integration suite `global-provisioned-autoscaled` (`make integration-global-provisioned-autoscaled`, workflow choice of the same name). It creates a provisioned, autoscaled table with a GSI and a replica in a second region (`TF_VAR_replica_region`, environment variable `AWS_INTEGRATION_REPLICA_REGION`) in one apply. The fixture gains `region` and `replica_region` outputs, and the integration IAM policy gains the replica and replication service-linked role permissions.
- Documentation of resource-policy `Deny` failure modes (self-lockout, denying the replication service-linked role) and of the policy size limit, plus a **Deferred items** list in `docs/DESIGN.md`.

### Changed

- `timeouts` defaults to `{}` and is non-nullable. Passing `null` still works and means the same thing: provider defaults (30m create, 60m update, 10m delete). The `timeouts` and `on_demand_throughput` descriptions now state what null means.
- The resource policy is rendered from a template whose default `Resource` entries are filled in with the table ARN. The output is byte-identical to 1.0.0.
- Version comments in `.github/workflows/integration.yml` now match the pinned SHAs (`actions/checkout` v7.0.1, `aws-actions/configure-aws-credentials` v6.3.0).

### Upgrade notes

- **Autoscaled global tables built before this release in two applies** (autoscaling first, replicas added later) keep their replicas in AWS, because the `autoscaled` variant now ignores `replica`. Before the first apply, import each replica into its new address, or the plan tries to create a replica that already exists and fails:

  ```hcl
  import {
    to = module.orders.aws_dynamodb_table_replica.this["eu-west-1"]
    id = "orders:us-east-1" # <table name>:<table region>
  }
  ```

- Tables whose caller sets `tags.Name`: expect an in-place tag update.
- Tables on the AWS owned key with a keyed replica: the plan fails until the posture is made symmetric.

## [1.0.0] - 2026-09-24

Breaking release. One module call still provisions one table, but every feature a production table needs is now a typed input, every cross-input rule fails at plan time, and the interface is reshaped around feature groups. [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md) maps every 0.1.x input to its replacement, lists the settings that keep the existing table, and gives ready-to-paste `moved` blocks.

### Added

- Submodule `autoscaling`: Application Auto Scaling for a PROVISIONED table and its global secondary indexes, one scalable target and one target-tracking policy per dimension (`table_read`, `table_write`, `index_<name>_read`, `index_<name>_write`), with its own tests and usable standalone from a Git source.
- Root `autoscaling` input that selects a second, otherwise identical table resource (`aws_dynamodb_table.autoscaled[0]`) with `ignore_changes` on capacities and indexes, so the scaler and Terraform do not fight; `scripts/check-resource-variants.sh` keeps the two bodies identical.
- `local_secondary_indexes` (at most five, projection rules shared with GSIs, table `range_key` required).
- `stream` (view type), `replicas` keyed by region with per-region KMS key, recovery, deletion protection, tag propagation, and consistency mode, and the preconditions that make replicas succeed at apply time.
- `table_class`, `on_demand_throughput` on the table and per GSI, `timeouts`.
- `resource_policy_statements` rendered with `jsonencode` into `aws_dynamodb_resource_policy`: sorted, null-free, `resources` defaulting to the table and every index, wildcard principals requiring a condition.
- `contributor_insights_enabled` and `contributor_insights_indexes` (`aws_dynamodb_contributor_insights` on the table and per named GSI).
- `kinesis_stream_arn` with `kinesis_approximate_creation_date_time_precision` (`aws_dynamodb_kinesis_streaming_destination`).
- `point_in_time_recovery.recovery_period_in_days` and `ttl.enabled`.
- Plan-time enforcement of the attribute contract: every key attribute declared, every declared attribute used, with the offending names in the error.
- Preconditions for capacities against `billing_mode` and autoscaling bounds, on-demand limits against billing mode, unique index names, the LSI `range_key` requirement, the TTL attribute, autoscaling and Contributor Insights index references, and replica prerequisites.
- Advisory `check` blocks that warn without blocking: `deletion_protection_disabled` and `point_in_time_recovery_disabled`.
- Outputs `name`, `stream_label`, `hash_key`, `range_key`, `billing_mode`, `table_class`, `global_secondary_index_arns`, `local_secondary_index_arns`, `replica_arns`, `autoscaling_target_resource_ids`, `autoscaling_policy_arns`, and `resource_policy`.
- Contract tests with `mock_provider` covering every default, validation, precondition, feature group, and the variant selection; a submodule test suite.
- Credential-driven integration suites in `tests/integration/` (`smoke` and `provisioned-autoscaled`) with a disposable fixture module, `make integration-smoke` and `make integration-provisioned-autoscaled` targets, a dispatch-only `integration` workflow that assumes a role through GitHub OIDC from the protected `integration` environment, and the IAM trust and permissions documents the role needs.
- Five executable examples: `minimal`, `complete`, `provisioned-autoscaled`, `global-table`, `multiple-tables`.
- `docs/DESIGN.md`, `docs/UPGRADE-1.0.md`, the submodule README, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, repository standards (`Makefile`, pre-commit, tflint, terraform-docs, Checkov, Trivy, Dependabot, issue and pull request templates, CODEOWNERS), and a per-directory CI quality matrix.

### Changed

- **Breaking:** `attributes` is `map(string)` (`{ pk = "S" }`) instead of `map(object({ type = string }))`, and a declared attribute that no key uses is rejected at plan time instead of by the API at apply time.
- **Breaking:** `ttl_attribute_name` is replaced by `ttl = { attribute_name, enabled }`.
- **Breaking:** `kms_key_arn` is replaced by `server_side_encryption = { kms_key_arn }`. Encryption at rest is always enabled and the ARN is validated as a full key ARN.
- **Breaking:** `point_in_time_recovery_enabled` is replaced by `point_in_time_recovery = { enabled, recovery_period_in_days }`.
- **Breaking:** the table resource address is `aws_dynamodb_table.this[0]` (or `aws_dynamodb_table.autoscaled[0]` with autoscaling) instead of `aws_dynamodb_table.this`.
- **Breaking:** `name` is validated (3 to 255 characters of `[a-zA-Z0-9_.-]`), as are index names, attribute types, capacities, and every enumerated input.
- **Breaking:** `global_secondary_indexes` capacities are rejected on a `PAY_PER_REQUEST` table and required (or covered by autoscaling) on a `PROVISIONED` table; `INCLUDE` projections require `non_key_attributes` and the other projections forbid them.
- **Breaking:** the `stream_arn` output is `null` unless `stream` is declared.
- The module adds a `Name` tag to the table. Caller tags pass through unchanged.
- A disabled TTL renders no block instead of an empty disabled block.
- AWS provider constraint raised from `>= 6.0, < 7.0` to `>= 6.35.0, < 7.0.0`.

### Removed

- **Breaking:** `terraform_data.input_contract`. Preconditions live on the table resource; the `terraform` provider is no longer required.

### Fixed

- A `PROVISIONED` table with a GSI that had no capacities failed at apply time; the module now requires them (or autoscaling) at plan time and names the index.
- An attribute declared but unused by any key failed at apply time with an API error; it is now rejected at plan time with the attribute named.

## [0.1.2] - 2026-09-22

### Changed

- Provider checksums locked for every supported runner platform.

## [0.1.1] - 2026-09-22

### Added

- Generated module reference in the README.

## [0.1.0] - 2026-09-22

### Added

- Versioned Terraform module for encrypted DynamoDB tables with typed primary and secondary-index definitions, point-in-time recovery, deletion protection, TTL, and optional customer-managed KMS encryption.

[Unreleased]: https://github.com/hatan4ik/aws.modules.dynamodb/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hatan4ik/aws.modules.dynamodb/compare/v0.1.2...v1.0.0
[0.1.2]: https://github.com/hatan4ik/aws.modules.dynamodb/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/hatan4ik/aws.modules.dynamodb/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hatan4ik/aws.modules.dynamodb/releases/tag/v0.1.0
