variable "name" {
  description = "Prefix for resource names, e.g. \"shop-dev\"."
  type        = string
}

variable "vpc_cidr" {
  description = "IP address range for the whole VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block, e.g. 10.0.0.0/16."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to spread subnets across (2 or 3)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3; high availability needs at least 2."
  }
}

variable "flow_logs_traffic_type" {
  description = "VPC Flow Logs capture: REJECT (blocked traffic only, cheapest), ALL, or null to disable."
  type        = string
  default     = "REJECT"

  validation {
    condition     = var.flow_logs_traffic_type == null || contains(["ACCEPT", "REJECT", "ALL"], coalesce(var.flow_logs_traffic_type, "x"))
    error_message = "flow_logs_traffic_type must be ACCEPT, REJECT, ALL, or null."
  }
}

variable "flow_logs_retention_days" {
  type    = number
  default = 14
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cheaper, but a single-AZ dependency). false = one per AZ (highly available, costs more)."
  type        = bool
  default     = true
}
