variable "name" {
  description = "Prefix for resource names. Keep it short: load balancer names are limited to 32 characters."
  type        = string

  validation {
    condition     = length(var.name) <= 24
    error_message = "name must be 24 characters or fewer so derived ALB and target group names fit AWS limits."
  }
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Subnets for the internet-facing load balancer."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Private subnets for the app servers."
  type        = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "app_image" {
  description = "Full container image reference, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/shop-dev-app:v1."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repository the instances may pull from (least privilege)."
  type        = string
}

variable "app_port" {
  type    = number
  default = 3000
}

variable "instance_type" {
  description = "x86 type so the image built on a normal PC/CI runner runs as-is."
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "cpu_target_percent" {
  description = "Auto Scaling adds or removes instances to keep average CPU near this value."
  type        = number
  default     = 50
}

variable "db_address" {
  type = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type = string
}

variable "db_secret_arn" {
  description = "Secrets Manager secret (managed by RDS) with the database username and password."
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate for HTTPS. null = HTTP only (acceptable for a short demo, not for real users)."
  type        = string
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 14
}
