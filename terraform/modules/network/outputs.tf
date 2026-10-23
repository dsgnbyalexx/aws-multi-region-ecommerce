output "vpc_id" {
  value = aws_vpc.this.id
}

output "availability_zones" {
  value = local.azs
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.db[*].id
}
