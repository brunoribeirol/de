# Remote state in the course's shared S3 backend (partial configuration).
# Account-specific values (bucket, key, region, lock table) come from
# backend.hcl, which is gitignored:
#   terraform init -migrate-state -backend-config=backend.hcl
# workspace_key_prefix: non-default workspaces store state under
# eda-a12/<workspace>/<key>; the default workspace uses <key> directly.
terraform {
  backend "s3" {
    workspace_key_prefix = "eda-a12"
  }
}
