# CONTRATO — o verifica.sh lê estes nomes. Preserve-os na refatoração.
output "bucket_name"    { value = aws_s3_bucket.lake.bucket }
output "database_name"  { value = aws_glue_catalog_database.db.name }
output "table_name"     { value = aws_glue_catalog_table.corridas.name }
output "workgroup_name" { value = aws_athena_workgroup.wg.name }
output "teto_bytes"     { value = var.teto_bytes }
