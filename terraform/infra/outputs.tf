output "caller_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS account ID executing the plan/apply"
}

output "ssm_parameter_arn" {
  value       = aws_ssm_parameter.hello.arn
  description = "ARN of the created SSM parameter"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.hello.name
  description = "Name of the created log group"
}
