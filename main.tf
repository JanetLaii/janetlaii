locals {
  tags = merge({ Name = random_pet.name.id }, var.tags)
}

resource "random_pet" "name" {
  length = 2
}

resource "aws_launch_template" "main" {
  description   = "The launch template of the compute deployment for TFE."
  image_id      = var.os == "ubuntu" ? data.aws_ami.ubuntu.id : data.aws_ami.rhel.id
  instance_type = var.instance_type
  name          = "tfe-${random_pet.name.id}-main"
  tags          = local.tags
  user_data     = module.user_data.base64_encoded
  key_name      = var.key_name

  vpc_security_group_ids = [
    aws_security_group.asg.id,
  ]

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = true
      encrypted             = true
      iops                  = contains(["io1", "io2"], var.volume_type) ? var.iops : null
      volume_size           = var.volume_size
      volume_type           = var.volume_type
    }
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.require_imdsv2 ? "required" : "optional"
    http_put_response_hop_limit = 2
  }
}

resource "aws_autoscaling_group" "main" {
  max_size = var.max_size
  min_size = var.min_size

  desired_capacity          = var.max_size
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = var.health_check_type
  load_balancers            = [aws_elb.load_balancer.id]
  name                      = "tfe-${random_pet.name.id}-main"
  vpc_zone_identifier       = var.vpc.private_subnets
  wait_for_capacity_timeout = 0

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupStandbyCapacity",
    "GroupTerminatingCapacity",
    "GroupTerminatingInstances",
    "GroupTotalCapacity",
    "GroupTotalInstances",
  ]
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }
  dynamic "tag" {
    for_each = local.tags

    content {
      key                 = tag.key
      propagate_at_launch = true
      value               = tag.value
    }
  }
}
