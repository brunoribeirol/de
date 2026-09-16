# =============================================================================
# Root module — wires inputs into the "lake" module. The six data-lake resources
# live in modules/lake/ (DECISAO 01); provider, variable validation, and the
# contract outputs stay here.
# =============================================================================

module "lake" {
  source     = "./modules/lake"
  sufixo     = var.sufixo
  teto_bytes = var.teto_bytes
}
