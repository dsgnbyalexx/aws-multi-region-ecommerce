# Primary-region environment. A disaster-recovery copy in us-west-2 would be a
# second environment that calls the same modules with region = "us-west-2"
# (designed, not implemented; see docs/architecture.md).

provider "aws" {
  region = var.region

  # Applied to every resource that supports tags: lets you find, cost and
  # clean up everything this project created.
  default_tags {
    tags = {
      Project     = "aws-multi-region-ecommerce"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name = "shop-${var.environment}"
}

# ---------- Container registry ----------

resource "aws_ecr_repository" "app" {
  name                 = "${local.name}-app"
  image_tag_mutability = "IMMUTABLE" # a tag always means the same image
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ---------- Tiers ----------

module "network" {
  source             = "../../modules/network"
  name               = local.name
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}

module "security" {
  source                = "../../modules/security"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
}

module "database" {
  source              = "../../modules/database"
  name                = local.name
  subnet_ids          = module.network.db_subnet_ids
  security_group_id   = module.security.db_security_group_id
  instance_class      = var.db_instance_class
  multi_az            = var.db_multi_az
  deletion_protection = var.db_deletion_protection
  skip_final_snapshot = var.db_skip_final_snapshot
}

module "app" {
  source                = "../../modules/app"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  app_subnet_ids        = module.network.app_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  app_security_group_id = module.security.app_security_group_id
  app_image             = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
  ecr_repository_arn    = aws_ecr_repository.app.arn
  instance_type         = var.instance_type
  min_size              = var.asg_min_size
  max_size              = var.asg_max_size
  desired_capacity      = var.asg_desired_capacity
  db_address            = module.database.address
  db_port               = module.database.port
  db_name               = module.database.db_name
  db_secret_arn         = module.database.master_user_secret_arn
  certificate_arn       = var.certificate_arn
}

# ---------- Cost guardrail ----------
# AWS Budgets alerts are NOT a spending cap: charges continue until you
# delete resources. Billing data can lag by several hours.

resource "aws_budgets_budget" "monthly" {
  count        = var.budget_alert_email == null ? 0 : 1
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
