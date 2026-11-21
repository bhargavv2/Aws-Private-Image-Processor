output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.worker.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.worker.arn
}

output "security_group_id" {
  description = "Security group ID of the EC2 worker"
  value       = aws_security_group.worker.id
}

output "iam_role_name" {
  description = "IAM Role Name for EC2 worker"
  value       = aws_iam_role.worker.name
}

output "iam_role_arn" {
  description = "IAM Role ARN for EC2 worker"
  value       = aws_iam_role.worker.arn
}

output "launch_template_id" {
  description = "Launch Template ID"
  value       = aws_launch_template.worker.id
}
