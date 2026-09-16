output "bucket_name" {
  description = "State bucket — the `bucket` value in backend.hcl."
  value       = aws_s3_bucket.tfstate.id
}

output "bucket_arn" {
  description = "State bucket ARN."
  value       = aws_s3_bucket.tfstate.arn
}

output "lock_table_name" {
  description = "Lock table in use — the `dynamodb_table` value in backend.hcl."
  value       = data.aws_dynamodb_table.lock.name
}

output "regiao" {
  description = "Region the bucket lives in — the `region` value in backend.hcl."
  value       = var.regiao
}

# Rendered so a consumer stack's backend.hcl is copied from real state instead
# of retyped. The `key` carries the individual suffix because the bucket belongs
# to the group: two teammates on the same stack must not share one key.
output "backend_hcl" {
  description = "backend.hcl template for a stack that uses this backend."
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.tfstate.id}"
    key            = "<stack>/${var.owner}/terraform.tfstate"
    region         = "${var.regiao}"
    dynamodb_table = "${data.aws_dynamodb_table.lock.name}"
    encrypt        = true
  EOT
}
