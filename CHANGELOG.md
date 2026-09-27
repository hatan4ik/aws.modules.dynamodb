# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

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
