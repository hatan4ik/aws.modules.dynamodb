# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.x | Yes. Security fixes and functional fixes on the latest minor release. |
| 0.1.x | Security fixes only, until 2026-12-31. Upgrade with [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md). |
| Unreleased `main` | Not supported for production use. |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository: open the Security tab and choose "Report a vulnerability". Do not open a public issue, pull request, or discussion for a security problem.

Include the module version or commit SHA, the inputs that reproduce the problem, the resulting plan or policy, and the impact you see.

## What counts

- A module default that weakens security: a table created without encryption at rest, without point-in-time recovery, or without deletion protection, or a replica that ends up on a different encryption posture than its table.
- A validation bypass: an input the module claims to reject at plan time but that reaches the provider, including a wildcard principal accepted without a condition in `resource_policy_statements`.
- A rendered resource policy broader than the statements declared: an extra action, resource, or principal, a dropped condition, or a Deny turned into an Allow by rendering.
- A helper resource attached to a table the caller did not name, or a caller-supplied KMS key or Kinesis stream that the module modifies.
- A dependency problem in the release pipeline that could publish unverified code.

Findings in your own inputs (for example an Allow statement you declared for `"*"` with a permissive condition) or in AWS services themselves are out of scope here; report the latter to AWS.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships as a patch release of every supported line with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

The module is secure by default: encryption at rest that cannot be turned off, with the AWS owned key unless a customer managed key is named and a regional key required on every replica of such a table; point-in-time recovery and deletion protection on, with advisory checks that warn while either is off; no resource policy unless statements are declared, a condition required for any wildcard principal, and a rendered document that is sorted and null-free so diffs are meaningful; and no permissions granted to anyone by the module itself. Every claim is enforced by a validation, a precondition, or a `check` block with a `terraform test` case behind it. The full description is in the [Security model](README.md#security-model) section of the README, and the reasoning in [docs/DESIGN.md](docs/DESIGN.md).
