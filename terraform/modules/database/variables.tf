variable "name" {
  description = "Prefix for resource names."
  type        = string
}

variable "subnet_ids" {
  description = "Private database subnets (at least two AZs, required by RDS)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS needs subnets in at least two Availability Zones."
  }
}

variable "security_group_id" {
  description = "Security group that allows PostgreSQL from the app tier only."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL major version. Matches the local Docker image (postgres:17)."
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "Database server size. db.t4g.micro is the smallest Graviton (ARM) class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage_gb" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage_gb" {
  description = "Upper limit for automatic storage growth in GiB."
  type        = number
  default     = 50
}

variable "multi_az" {
  description = "true = synchronous standby in a second AZ with automatic failover (roughly doubles the instance cost)."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Name of the application database."
  type        = string
  default     = "shop"
}

variable "master_username" {
  description = "Admin username. The password is generated and stored in Secrets Manager by RDS."
  type        = string
  default     = "shop_admin"
}

variable "backup_retention_days" {
  description = "Days of automated backups (enables point-in-time recovery)."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Block accidental deletion. Keep true outside short-lived test environments."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "false = take a final snapshot when the database is destroyed."
  type        = bool
  default     = false
}
