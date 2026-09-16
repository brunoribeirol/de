# Inputs of the lake module. Validation and defaults stay in the root module,
# which owns the user-facing interface; the module just receives values.

variable "sufixo" {
  type        = string
  description = "Unique suffix used in every resource name (lowercase letters and digits)."
}

variable "teto_bytes" {
  type        = number
  description = "Athena WorkGroup bytes-scanned cutoff per query."
}
