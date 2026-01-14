###############################################################################
# VPC Module Outputs
###############################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "Public subnet ID (AZ1)"
  value       = aws_subnet.public.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs for ALBs"
  value       = var.public_subnet_cidr_az2 != "" ? [aws_subnet.public.id, aws_subnet.public_az2[0].id] : [aws_subnet.public.id]
}

output "private_web_subnet_id" {
  description = "Private web tier subnet ID"
  value       = aws_subnet.private_web.id
}

output "private_app_subnet_id" {
  description = "Private app tier subnet ID (AZ1)"
  value       = aws_subnet.private_app.id
}

output "private_app_subnet_ids" {
  description = "List of private app subnet IDs for internal ALBs"
  value       = var.private_app_cidr_az2 != "" ? [aws_subnet.private_app.id, aws_subnet.private_app_az2[0].id] : [aws_subnet.private_app.id]
}

output "private_data_subnet_id" {
  description = "Private data tier subnet ID (AZ1)"
  value       = aws_subnet.private_data.id
}

output "private_data_subnet_id_az2" {
  description = "Private data tier subnet ID (AZ2)"
  value       = aws_subnet.private_data_az2.id
}

output "private_data_subnet_ids" {
  description = "List of both data subnet IDs for RDS subnet group"
  value       = [aws_subnet.private_data.id, aws_subnet.private_data_az2.id]
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = var.enable_nat_gateway ? aws_eip.nat[0].public_ip : null
}

output "availability_zone" {
  description = "Availability zone used"
  value       = var.availability_zone
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}
