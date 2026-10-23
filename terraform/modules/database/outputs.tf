output "address" {
  description = "DNS name of the database. During a Multi-AZ failover it moves to the standby automatically."
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the generated credentials (not the secret itself)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "instance_arn" {
  value = aws_db_instance.this.arn
}
