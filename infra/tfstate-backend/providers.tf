provider "aws" {
  region = var.regiao

  # The account is shared by the whole class: tags are what makes it possible to
  # tell whose resources these are without reading names.
  default_tags {
    tags = {
      Disciplina = "EDA"
      Grupo      = var.grupo
      Owner      = var.owner
      Stack      = "tfstate-backend"
      ManagedBy  = "Terraform"
    }
  }
}
