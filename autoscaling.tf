module "autoscaling" {
  source = "./modules/autoscaling"
  count  = var.autoscaling == null ? 0 : 1

  table_name = local.table.name
  table      = var.autoscaling.table
  indexes    = var.autoscaling.indexes
  tags       = var.tags
}
