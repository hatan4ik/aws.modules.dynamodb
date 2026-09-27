provider "aws" {
  region = var.region
}

module "table" {
  source = "../../"

  name       = var.name
  hash_key   = "pk"
  range_key  = "sk"
  attributes = { pk = "S", sk = "S" }

  tags = var.tags
}
