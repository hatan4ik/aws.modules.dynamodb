# Integration suites

The suites in this directory apply the module for real in **your** AWS account
and destroy everything afterwards. They complement the contract tests in
`tests/`, which run with `mock_provider`, need no credentials, and use the AWS
documentation placeholder account `123456789012` and fake ARNs on purpose:
they prove the module's interface and rendering, not that AWS accepts it. These
suites prove the latter.

Nothing here is tied to an account, region, or landing zone. Credentials and
the region come from the environment; the only prerequisites are a unique
table name and the caller's account identity, which [`setup/`](setup/)
resolves with a random suffix so concurrent runs never collide.

| Suite | What it proves | Needs | Typical time |
| --- | --- | --- | --- |
| `smoke.tftest.hcl` | An on-demand table with a GSI, TTL, point-in-time recovery, a stream of new and old images, and a resource-based policy are accepted by the DynamoDB APIs, and every output reflects the real ARNs. | credentials, region | about 3 minutes |
| `provisioned-autoscaled.tftest.hcl` | A PROVISIONED table and its GSI register four scalable targets and target-tracking policies with Application Auto Scaling through the `autoscaled` table variant. | credentials, region | about 4 minutes |

Both suites set `deletion_protection_enabled = false` so `terraform test` can
destroy the table, and expect the module's `deletion_protection_disabled`
check to warn. Tables are billed for minutes; the smoke table is on-demand and
the provisioned table runs at 2 read and 2 write units.

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
export AWS_REGION=<region>
make integration-smoke                   # terraform init -test-directory=tests/integration && terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl
make integration-provisioned-autoscaled
```

The credentials need the permissions in
[`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json)
(replace `<ACCOUNT_ID>`). Table actions are scoped to names starting with
`dynamodb-it-`, which is what the fixture produces; the service-linked role
statement lets Application Auto Scaling create its DynamoDB role the first
time it is used in the account.

`terraform test` runs `tests/` only by default, so these suites never run in
the credential-free quality pipeline. The fixture module is excluded from the
Checkov and Trivy scans (`.checkov.yml`, `trivy.yaml`) because it is
short-lived test infrastructure, not a deployable pattern.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is dispatch-only
and assumes a role through GitHub OIDC. It reads everything account-specific
from the protected `integration` environment of the repository, so the code
stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region for the disposable tables. |

Dispatch with `gh workflow run integration.yml -f suite=smoke` (or
`provisioned-autoscaled`). Protect the environment with required reviewers so
a run cannot be started from a pull request by anyone with write access.

For this repository's owner the environment is prepared with the sandbox
region; the role ARN is added once the role exists in the sandbox account,
created through the platform's delivery IAM module with the trust policy above
and the subject `repo:hatan4ik/aws.modules.dynamodb:environment:integration`.
