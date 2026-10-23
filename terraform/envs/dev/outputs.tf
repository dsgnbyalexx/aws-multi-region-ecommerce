output "app_url" {
  description = "Open this in a browser after deployment."
  value       = module.app.app_url
}

output "ecr_repository_url" {
  description = "Push the app image here before deploying."
  value       = aws_ecr_repository.app.repository_url
}

output "autoscaling_group_name" {
  value = module.app.autoscaling_group_name
}

output "app_log_group" {
  value = module.app.log_group_name
}

output "db_secret_arn" {
  description = "Where the database credentials live (the ARN is not the secret)."
  value       = module.database.master_user_secret_arn
}

output "availability_zones" {
  value = module.network.availability_zones
}
