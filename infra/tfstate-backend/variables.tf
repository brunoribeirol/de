variable "regiao" {
  type        = string
  description = "AWS region for the state bucket. Must match the region in backend.hcl."
  default     = "us-east-1"
}

# The backend belongs to the GROUP (one bucket per IAM login, as in
# eda-tfstate-grupo02, created by another group), while lab resources are named
# after the individual suffix. Keeping the two apart is what lets teammates share
# one backend without colliding -- they differ by `key`, not by bucket.
variable "grupo" {
  type        = string
  description = "Group identifier owning this backend, matching the IAM login (e.g. grupo07)."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.grupo))
    error_message = "Use apenas letras minusculas e numeros (sem hifen)."
  }
}

variable "owner" {
  type        = string
  description = "Individual suffix of whoever applies this stack, used only for tagging (e.g. brlla)."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.owner))
    error_message = "Use apenas letras minusculas e numeros (sem hifen)."
  }
}

variable "lock_table_name" {
  type        = string
  description = "Existing DynamoDB lock table, shared by the class. Read, never managed by this stack."
  default     = "eda-tflock"
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "How long superseded state versions are kept before expiring."
  default     = 90
}
