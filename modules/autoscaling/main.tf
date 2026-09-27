locals {
  metric_types = {
    read  = "DynamoDBReadCapacityUtilization"
    write = "DynamoDBWriteCapacityUtilization"
  }

  scalable_dimensions = {
    table = { read = "dynamodb:table:ReadCapacityUnits", write = "dynamodb:table:WriteCapacityUnits" }
    index = { read = "dynamodb:index:ReadCapacityUnits", write = "dynamodb:index:WriteCapacityUnits" }
  }

  # One entry per scaled dimension: table_read, table_write, index_<name>_read,
  # index_<name>_write. Each carries the Application Auto Scaling addressing
  # next to the caller's bounds and targets.
  table_dimensions = var.table == null ? {} : {
    for direction in ["read", "write"] : "table_${direction}" => merge(var.table[direction], {
      resource_id        = "table/${var.table_name}"
      scalable_dimension = local.scalable_dimensions.table[direction]
      metric_type        = local.metric_types[direction]
    }) if var.table[direction] != null
  }

  index_dimensions = merge([
    for name, index in var.indexes : {
      for direction in ["read", "write"] : "index_${name}_${direction}" => merge(index[direction], {
        resource_id        = "table/${var.table_name}/index/${name}"
        scalable_dimension = local.scalable_dimensions.index[direction]
        metric_type        = local.metric_types[direction]
      }) if index[direction] != null
    }
  ]...)

  dimensions = merge(local.table_dimensions, local.index_dimensions)
}

resource "aws_appautoscaling_target" "this" {
  for_each = local.dimensions

  service_namespace  = "dynamodb"
  scalable_dimension = each.value.scalable_dimension
  resource_id        = each.value.resource_id
  min_capacity       = each.value.min_capacity
  max_capacity       = each.value.max_capacity

  tags = var.tags
}

resource "aws_appautoscaling_policy" "this" {
  for_each = local.dimensions

  name               = "${var.table_name}-${each.key}"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.target_utilization
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = each.value.metric_type
    }
  }
}
