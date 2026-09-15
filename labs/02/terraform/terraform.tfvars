# Copie este arquivo para terraform.tfvars e preencha.
#   cp terraform.tfvars.example terraform.tfvars

sufixo = "brlla"        # so minusculas, numeros e hifen

# DECISAO 05 — o teto que voce MEDIU (nao copie do lab).
# Rode a consulta larga sem teto, veja o Data scanned, e escolha.
teto_bytes = 12522547

# DECISAO 04 — os dias que voce vai registrar como particao (>= 3, incluindo hoje).
# Troque pelos dias reais; o do meio e o de hoje.
dias_particao = ["2026-09-06", "2026-09-03", "2026-08-30", "2026-08-31"]

