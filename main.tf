# Helper resources attached to the one table. Each exists only when declared
# and references the table by name or ARN, so it is created after the table
# and destroyed before it.

resource "aws_dynamodb_resource_policy" "this" {
  count = length(var.resource_policy_statements) == 0 ? 0 : 1

  resource_arn = local.table.arn
  policy       = local.resource_policy
}

resource "aws_dynamodb_contributor_insights" "this" {
  count = var.contributor_insights_enabled ? 1 : 0

  table_name = local.table.name
}

resource "aws_dynamodb_contributor_insights" "index" {
  for_each = var.contributor_insights_indexes

  table_name = local.table.name
  index_name = each.value
}

resource "aws_dynamodb_kinesis_streaming_destination" "this" {
  count = var.kinesis_stream_arn == null ? 0 : 1

  table_name                               = local.table.name
  stream_arn                               = var.kinesis_stream_arn
  approximate_creation_date_time_precision = var.kinesis_approximate_creation_date_time_precision
}
