# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "deletion_protection_disabled" {
  assert {
    condition     = var.deletion_protection_enabled
    error_message = "Deletion protection is off. A terraform destroy or a removed module block deletes the table and its data; keep deletion_protection_enabled = true outside short-lived environments."
  }
}

check "point_in_time_recovery_disabled" {
  assert {
    condition     = var.point_in_time_recovery.enabled
    error_message = "Point-in-time recovery is off. Accidental writes or deletes cannot be undone; keep point_in_time_recovery.enabled = true for any table holding data you would miss."
  }
}

# The autoscaled table variant ignores global_secondary_index (table.tf), so
# adding or removing a key of global_secondary_indexes on an existing
# autoscaled table changes nothing on the table while autoscaling.indexes and
# contributor_insights_indexes still plan resources for the declared index,
# which then fail at apply against an index that does not exist. The planned
# index set of the autoscaled variant is its prior state, so comparing it with
# the declared names detects the drift; on create the two always match.
check "autoscaled_index_drift" {
  assert {
    condition = var.autoscaling == null ? true : (
      sort([for index in aws_dynamodb_table.autoscaled[0].global_secondary_index : index.name]) == sort(keys(var.global_secondary_indexes))
    )
    error_message = "global_secondary_indexes no longer match the indexes on the autoscaled table, and the autoscaled variant ignores index changes. Apply index changes as README, Lifecycle notes describes (through the API, or by moving the table to the this variant) before relying on autoscaling.indexes or contributor_insights_indexes for a new index."
  }
}
