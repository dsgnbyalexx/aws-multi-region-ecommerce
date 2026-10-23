data "aws_region" "current" {}
data "aws_partition" "current" {}

# Latest Amazon Linux 2023 image, looked up from AWS's public parameter.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  https_enabled = var.certificate_arn != null
  registry      = split("/", var.app_image)[0]
}

# ======================= Load balancer =======================

# Accepted: this is a public storefront, so the load balancer must be
# internet-facing. Access can be narrowed with allowed_ingress_cidrs.
#trivy:ignore:AWS-0053
resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [var.alb_security_group_id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name     = "${var.name}-app"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # Give in-flight requests 30 s to finish when an instance is removed.
  # Pairs with the app's graceful SIGTERM shutdown.
  deregistration_delay = 30

  # The ALB has ONE health check, used for routing AND (because the ASG uses
  # ELB health checks) for replacing instances. It points at the shallow
  # /health endpoint: a database outage must not make Auto Scaling terminate
  # every healthy app server. See the README "Design decisions".
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# Accepted for the demo only: without a domain there is no ACM certificate,
# so HTTP is served directly. Setting certificate_arn turns this listener
# into an HTTP -> HTTPS redirect.
#trivy:ignore:AWS-0054
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    # With a certificate: redirect HTTP to HTTPS. Without one: serve directly.
    type             = local.https_enabled ? "redirect" : "forward"
    target_group_arn = local.https_enabled ? null : aws_lb_target_group.app.arn

    dynamic "redirect" {
      for_each = local.https_enabled ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = local.https_enabled ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ======================= Logs =======================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.name}/app"
  retention_in_days = var.log_retention_days
}

# ======================= IAM: what the app servers may do =======================

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-app"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

# Session Manager shell access instead of SSH: no open port 22, no key pairs.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadDatabaseSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }

  statement {
    sid = "EcrLogin"
    # GetAuthorizationToken does not support resource-level restrictions,
    # so AWS requires "*" here. Pulling is restricted below.
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullAppImage"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid       = "WriteAppLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.name}-app"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app"
  role = aws_iam_role.app.name
}

# ======================= App servers =======================

resource "aws_launch_template" "app" {
  name_prefix            = "${var.name}-app-"
  image_id               = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type          = var.instance_type
  vpc_security_group_ids = [var.app_security_group_id]
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    region        = data.aws_region.current.region
    registry      = local.registry
    image         = var.app_image
    app_port      = var.app_port
    db_host       = var.db_address
    db_port       = var.db_port
    db_name       = var.db_name
    db_secret_arn = var.db_secret_arn
    log_group     = aws_cloudwatch_log_group.app.name
  }))

  # IMDSv2 only (blocks a common credential-theft technique). Hop limit 1
  # means containers on the instance cannot reach the metadata service.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-app" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${var.name}-app" }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.name}-app"
  vpc_zone_identifier = var.app_subnet_ids # spread across AZs
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  target_group_arns   = [aws_lb_target_group.app.arn]

  # Replace instances that fail the load balancer's health check.
  health_check_type         = "ELB"
  health_check_grace_period = 180

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # When the launch template changes (new image, new AMI), replace instances
  # gradually, keeping at least half healthy and serving.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target_percent
  }
}
