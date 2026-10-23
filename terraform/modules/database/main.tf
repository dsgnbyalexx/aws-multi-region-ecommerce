resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.name}-db" }
}

# Force encrypted (TLS) connections. The app connects with PGSSLMODE=verify-full.
resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-postgres${var.engine_version}"
  family = "postgres${var.engine_version}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.master_username
  # RDS generates the password and stores it in AWS Secrets Manager, so it
  # never appears in this code, in variables, or in Terraform state.
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = var.backup_retention_days
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.name}-postgres-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = "${var.name}-postgres" }
}
