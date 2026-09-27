# Contributing

Thank you for improving `aws.modules.dynamodb`. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in every README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root, the submodule, every example directory, and the integration fixture. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root and in `modules/autoscaling`. No credentials are needed. |
| `make variants` | `scripts/check-resource-variants.sh table.tf aws_dynamodb_table this autoscaled`: fails when the two table resource bodies differ in anything other than `count` and `ignore_changes`. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. CI runs `terraform init` before the docs drift check, so a lock file missing the Linux hash gets rewritten and fails that check. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason, like the one on the table resources for the AWS owned key default. |
| `make check` | `fmt`, `validate`, `lint`, `test`, `variants`, `docs-check`, `security`, in that order. |

## Integration suites

`tests/integration/` holds credential-driven suites that apply the module for real and destroy everything afterwards. They are never part of `make check` or the quality pipeline. Run them against your own account before a release that touches resource behaviour:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>
make integration-smoke                   # about 3 minutes: on-demand table, GSI, TTL, PITR, stream, resource policy
make integration-provisioned-autoscaled  # about 4 minutes: provisioned table and GSI under Application Auto Scaling
```

Add a suite when a feature's correctness depends on the AWS API rather than on rendering (for example a new table integration). Keep fixtures in `tests/integration/setup`, keep every value derived from the environment or the fixtures, and never reference a real account, region, key, or stream.

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl` for the root and `modules/autoscaling/tests/*.tftest.hcl` for the submodule. Each file starts with `mock_provider "aws" {}` and a `variables` block holding a valid baseline; each `run` overrides only what it exercises.
- Use `command = plan`. Nothing here talks to AWS, so tests run in seconds and in CI without credentials. The one `command = apply` run, in `tests/resource_policy.tftest.hcl`, uses a `mock_resource` default ARN to assert the policy's default `Resource` list, which derives from the table ARN.
- Validations are tested with `expect_failures`. Point it at the object that carries the check: `[var.attributes]` for a variable validation, `[aws_dynamodb_table.this]` (or `[aws_dynamodb_table.autoscaled]` when `autoscaling` is set) for a table precondition, `[output.target_resource_ids]` for the submodule's output precondition, `[check.deletion_protection_disabled]` for a `check` block. A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too.
- Assertions must not depend on unknown values. With a mock provider, computed attributes such as ARNs, stream labels, and optional-computed attributes left null (GSI capacities on an on-demand table, `stream_view_type` without a stream) are unknown at plan time. A set that contains an unknown element has an unknown length, so count `global_secondary_index` and `replica` entries with `length([for index in ... : index.name])` and read their attributes with `one([for ... if ...])`, as `tests/indexes.tftest.hcl` and `tests/replicas.tftest.hcl` do.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so `var.x == null || var.x.field > 0` fails when `x` is null. Guard with a conditional instead: `var.x == null ? true : var.x.field > 0`. This applies to validations, preconditions, and test assertions alike.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.
- The two `aws_dynamodb_table` resource blocks in `table.tf` must stay identical apart from `count` and `lifecycle.ignore_changes`. A change to one is a change to both; `make variants` enforces it and `tests/autoscaling.tftest.hcl` covers the `autoscaled` variant.

## Where to add a feature

The submodule owns one concern and has one reason to change. The root owns the table and its directly attached helpers.

| Concern | Lives in |
| --- | --- |
| Scaling dimensions, metrics, cooldowns | `modules/autoscaling`. The root passes `var.autoscaling` fields through and only checks that scaled indexes exist. |
| A table argument or block (a new index attribute, a new throughput setting) | Root `table.tf`, applied to both table resources, with its variable in `variables.tf` and any derived value in `locals.tf`. |
| A helper resource attached to the table (policy, insights, streaming destination) | Root `main.tf`, created only when its input is declared, referencing the table through `local.table`. |
| Cross-variable validation (an index key against `attributes`, a capacity against `billing_mode` or an autoscaling bound, a replica prerequisite) | A `lifecycle.precondition` on both table resources in `table.tf`, with the offending names in the message. Single-variable rules stay in `variables.tf`. |
| A configuration that is valid but usually unintended | `checks.tf`, as a `check` block that warns without blocking. |
| Rendered JSON (the resource policy) | `locals.tf` with `jsonencode`, sorted and null-free, so tests can decode and assert on it. |

Rules that apply everywhere: no data sources (derive from inputs), every variable has a description, a type, and a validation where a wrong value would otherwise fail at apply time, every output has a description, defaults are the secure choice, and every external dependency is an identifier the caller passes in.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the submodule or root file the change touches.

```text
feat(autoscaling): add scheduled capacity actions
fix(table): reject a TTL attribute that is also an index key
docs: describe the autoscaled table variant
test(replicas): cover per-region deletion protection overrides
feat!: replace ttl_attribute_name with the ttl object
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in the upgrade guide.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] Both `aws_dynamodb_table` blocks were updated if table arguments changed (`make variants`).
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and an update to `docs/UPGRADE-<major>.md`.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] No data sources, no hard-coded account, region, or partition, no new defaults that weaken security.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.dynamodb vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag, never from `main`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies that the signed tag points at the revision it checked out, then formatting, validation, tests, and generated docs, and publishes the GitHub release. A maintenance release of an older line is cut from that line's commit the same way.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.dynamodb.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.
