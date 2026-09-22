# aws.modules.dynamodb

Versioned Terraform module for encrypted DynamoDB tables with typed primary and
secondary-index definitions, point-in-time recovery, deletion protection, TTL,
and optional customer-managed KMS encryption. The caller supplies only
attributes used by keys and indexes, as required by the DynamoDB API.
