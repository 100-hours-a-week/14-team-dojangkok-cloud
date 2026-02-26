# ==============================================
# CodeDeploy Module
# Application + Deployment Groups (Blue/Green)
# ==============================================

resource "aws_codedeploy_app" "this" {
  for_each = var.applications

  compute_platform = "Server"
  name             = each.value.name

  tags = {
    Name = each.value.name
  }
}

resource "aws_codedeploy_deployment_group" "this" {
  for_each = var.deployment_groups

  app_name               = aws_codedeploy_app.this[each.value.app_key].name
  deployment_group_name  = each.value.name
  service_role_arn       = var.codedeploy_role_arn
  deployment_config_name = lookup(each.value, "deployment_config", "CodeDeployDefault.AllAtOnce")
  autoscaling_groups     = lookup(each.value, "autoscaling_groups", null)

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  # Blue/Green deployment style
  dynamic "deployment_style" {
    for_each = lookup(each.value, "deployment_type", null) == "BLUE_GREEN" ? [1] : []
    content {
      deployment_option = "WITH_TRAFFIC_CONTROL"
      deployment_type   = "BLUE_GREEN"
    }
  }

  # In-place deployment style (default)
  dynamic "deployment_style" {
    for_each = lookup(each.value, "deployment_type", null) != "BLUE_GREEN" && lookup(each.value, "target_group_name", null) != null ? [1] : []
    content {
      deployment_option = "WITH_TRAFFIC_CONTROL"
      deployment_type   = "IN_PLACE"
    }
  }

  # Blue/Green config
  dynamic "blue_green_deployment_config" {
    for_each = lookup(each.value, "deployment_type", null) == "BLUE_GREEN" ? [1] : []
    content {
      deployment_ready_option {
        action_on_timeout = "CONTINUE_DEPLOYMENT"
      }

      green_fleet_provisioning_option {
        action = "COPY_AUTO_SCALING_GROUP"
      }

      terminate_blue_instances_on_deployment_success {
        action                           = "TERMINATE"
        termination_wait_time_in_minutes = lookup(each.value, "termination_wait_minutes", 5)
      }
    }
  }

  dynamic "ec2_tag_set" {
    for_each = lookup(each.value, "ec2_tag_filters", null) != null ? [1] : []
    content {
      dynamic "ec2_tag_filter" {
        for_each = each.value.ec2_tag_filters
        content {
          key   = ec2_tag_filter.value.key
          type  = ec2_tag_filter.value.type
          value = ec2_tag_filter.value.value
        }
      }
    }
  }

  dynamic "load_balancer_info" {
    for_each = lookup(each.value, "target_group_name", null) != null ? [1] : []
    content {
      target_group_info {
        name = each.value.target_group_name
      }
    }
  }
}
