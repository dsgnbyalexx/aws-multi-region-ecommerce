# Three subnet tiers in each Availability Zone (AZ):
#   public  - load balancer and NAT gateway; routes to the internet gateway
#   app     - EC2 app servers; no public IPs; outbound internet via NAT only
#   db      - RDS; no route to the internet at all

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs       = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  nat_count = var.single_nat_gateway ? 1 : var.az_count
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for RDS endpoint names to resolve

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

# ---------- Subnets (one per AZ per tier) ----------
# cidrsubnet(10.0.0.0/16, 8, n) -> 10.0.n.0/24
#   public: 10.0.0.0/24, 10.0.1.0/24 ... app: 10.0.10.0/24 ... db: 10.0.20.0/24 ...

resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "app" {
  count             = var.az_count
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)

  tags = { Name = "${var.name}-app-${local.azs[count.index]}", Tier = "app" }
}

resource "aws_subnet" "db" {
  count             = var.az_count
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)

  tags = { Name = "${var.name}-db-${local.azs[count.index]}", Tier = "db" }
}

# ---------- Public routing ----------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------- NAT: lets private app servers reach out (ECR, SSM, Secrets Manager) ----------
# COST: each NAT gateway is billed per hour even when idle, plus per GB processed.

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name}-nat-${count.index}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------- App routing (one route table per AZ, so each can use its own NAT) ----------

resource "aws_route_table" "app" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-app-${local.azs[count.index]}" }
}

resource "aws_route" "app_nat" {
  count                  = var.az_count
  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "app" {
  count          = var.az_count
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# ---------- DB routing: local VPC traffic only, no internet route ----------

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-db" }
}

resource "aws_route_table_association" "db" {
  count          = var.az_count
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# Free S3 gateway endpoint: container image layers from ECR are stored in S3,
# so this keeps that traffic off the (billed) NAT gateway.
data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.app[*].id
  tags              = { Name = "${var.name}-s3-endpoint" }
}

# ---------- VPC Flow Logs: a record of network traffic, for security and troubleshooting ----------
# Default captures only REJECTED traffic (connections blocked by security
# groups or network ACLs), which keeps CloudWatch ingestion costs low.

locals {
  flow_logs_enabled = var.flow_logs_traffic_type != null
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = local.flow_logs_enabled ? 1 : 0
  name              = "/${var.name}/vpc-flow-logs"
  retention_in_days = var.flow_logs_retention_days
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count              = local.flow_logs_enabled ? 1 : 0
  name               = "${var.name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  count = local.flow_logs_enabled ? 1 : 0
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count  = local.flow_logs_enabled ? 1 : 0
  name   = "${var.name}-vpc-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count                = local.flow_logs_enabled ? 1 : 0
  vpc_id               = aws_vpc.this.id
  traffic_type         = var.flow_logs_traffic_type
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn         = aws_iam_role.flow_logs[0].arn
  tags                 = { Name = "${var.name}-flow-logs" }
}
