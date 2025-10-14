output "state_bucket"  { value = aws_s3_bucket.tf_state.bucket }
output "lock_table"    { value = aws_dynamodb_table.tf_lock.name }
output "deploy_bucket" { value = aws_s3_bucket.deploy.bucket }
