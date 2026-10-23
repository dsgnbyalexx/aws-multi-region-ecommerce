# Security groups are stateful firewalls. Each tier only accepts traffic from
# the tier directly in front of it:
#   internet --80/443--> ALB --3000--> app --5432--> database
# Rules reference security groups (not IP ranges), so they keep working as
# instances come and go.

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Load balancer: HTTP/HTTPS from allowed clients"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "App servers: traffic from the load balancer only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-app" }
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Database: PostgreSQL from app servers only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

# ---------- Load balancer ----------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each          = toset(var.allowed_ingress_cidrs)
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each          = toset(var.allowed_ingress_cidrs)
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward requests and health checks to app servers"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.app.id
}

# ---------- App servers ----------

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from the load balancer only"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL to the database"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.db.id
}

# Accepted risk: AWS API endpoints (ECR, Secrets Manager, SSM, CloudWatch) and
# the Amazon Linux package CDN use many changing public IPs, so HTTPS egress is
# open via the NAT gateway. Tighter alternative: VPC interface endpoints
# (billed per endpoint per AZ). Plain HTTP egress is deliberately NOT allowed.
#trivy:ignore:AWS-0104
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS out via NAT: ECR, SSM, Secrets Manager, CloudWatch, OS packages"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------- Database ----------
# No egress rules: the database never needs to start outbound connections.

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from app servers only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}
