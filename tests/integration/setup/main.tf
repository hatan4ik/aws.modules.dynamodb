# Disposable prerequisites for the integration suites: a unique table name and
# the identity of the caller, used as the principal of the resource policy
# under test. Nothing here is shared or long-lived; `terraform test` creates it
# in the caller's own account before the module under test and destroys it
# afterwards.

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name      = "${var.name_prefix}-${random_id.suffix.hex}"
  partition = split(":", data.aws_caller_identity.current.arn)[1]

  tags = merge(var.tags, {
    Name            = local.name
    IntegrationTest = "aws.modules.dynamodb"
    Disposable      = "true"
  })
}
