provider "aws" {
  region = var.region
}

# One module call is one table. A fleet is a for_each over the module block,
# so each table keeps its own plan, its own validation errors, and its own
# lifecycle while sharing the tags and naming convention.
module "table" {
  source   = "../../"
  for_each = var.tables

  name       = "${var.name_prefix}-${each.key}"
  hash_key   = each.value.hash_key
  range_key  = each.value.range_key
  attributes = each.value.attributes
  tags       = merge(var.tags, { Table = each.key })

  global_secondary_indexes = each.value.global_secondary_indexes

  ttl    = each.value.ttl_attribute == null ? null : { attribute_name = each.value.ttl_attribute }
  stream = each.value.stream_view_type == null ? null : { view_type = each.value.stream_view_type }
}
