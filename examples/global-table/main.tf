provider "aws" {
  region = var.region
}

module "table" {
  source = "../../"

  name       = var.name
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S" }
  tags       = var.tags

  # Replicas require a stream of new and old images and either on-demand
  # billing or autoscaling, so every region can absorb replicated writes.
  billing_mode = "PAY_PER_REQUEST"
  stream       = { view_type = "NEW_AND_OLD_IMAGES" }

  # The table uses a customer managed key, so every replica names its own
  # regional key: the encryption posture is the same in every region.
  server_side_encryption = { kms_key_arn = var.kms_key_arn }

  replicas = {
    for region, kms_key_arn in var.replica_kms_key_arns : region => {
      kms_key_arn = kms_key_arn
      # Recovery, deletion protection, and tags are inherited from the table.
    }
  }
}
