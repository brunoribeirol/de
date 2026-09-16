# Pinned to the same major provider version the labs use, so the backend stack
# and the stacks whose state it holds are never built by incompatible providers.
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block on purpose: this stack CREATES the remote backend, so its
  # own state has to live somewhere that exists beforehand -- the local disk.
  # See README.md ("Why the state of this stack is local").
}
