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
