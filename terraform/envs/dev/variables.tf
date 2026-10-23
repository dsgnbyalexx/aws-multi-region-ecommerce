variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Short environment name used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters/digits, starting with a letter."
  }
}

variable "app_image_tag" {
  description = "Tag of the app image in ECR to deploy, e.g. a git commit SHA. No default on purpose: deploys must be explicit."
  type        = string
}

variable "allowed_ingress_cidrs" {
  description = "Who can reach the load balancer. Prefer your own IP (x.x.x.x/32) while testing."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN to enable HTTPS."
  type        = string
  default     = null
}

# ---- Cost-sensitive switches (dev defaults favour low cost) ----

variable "az_count" {
  type    = number
  default = 2
}

variable "single_nat_gateway" {
  description = "Dev: one NAT gateway (cheaper). Production: false, one per AZ."
  type        = bool
  default     = true
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Dev: false (single instance). Production: true (standby in another AZ, roughly double the cost)."
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Dev: false so the environment can be torn down. Production: true."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Dev: true (no leftover snapshot to pay for). Production: false."
  type        = bool
  default     = true
}

variable "ecr_force_delete" {
  description = "Allow `terraform destroy` to delete the image repository even if it still contains images."
  type        = bool
  default     = true
}

# ---- Billing alert ----

variable "budget_alert_email" {
  description = "Email for AWS Budgets alerts. null = no budget is created."
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  type    = number
  default = 20
}
