# Declares the provider this module needs. The provider itself (region,
# default_tags) is configured only in the root module and inherited here.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
