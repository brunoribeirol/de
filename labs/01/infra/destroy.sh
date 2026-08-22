#!/usr/bin/env bash
# Derruba a sua stack e PROVA que nao sobrou nada. Rode da raiz do pacote.
#   ./infra/destroy.sh <seu-login>
set -euo pipefail

REGIAO="us-east-1"
LOGIN="${1:-}"

if [[ ! "$LOGIN" =~ ^[a-z0-9][a-z0-9-]{2,28}$ ]]; then
  echo "uso: ./infra/destroy.sh <seu-login>" >&2
  exit 1
fi

STACK="eda-a04-${LOGIN}"
BUCKET="eda-a04-lake-${LOGIN}"
DATABASE="eda_a04_raw_${LOGIN}"
WORKGROUP="eda-a04-wg-${LOGIN}"

echo "esvaziando s3://${BUCKET}"
aws s3 rm "s3://${BUCKET}" --recursive --region "$REGIAO" --only-show-errors || true

echo "apagando a stack ${STACK}"
aws cloudformation delete-stack --region "$REGIAO" --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --region "$REGIAO" --stack-name "$STACK"

# Cada checagem diz o que encontrou. Lista vazia e comando que falhou tem a
# mesma cara no --output text, e essa ambiguidade e pior do que nao conferir.
echo
echo "conferencia:"
pendencias=0

confere() {
  local rotulo="$1" achado="$2"
  if [[ -z "$achado" ]]; then
    printf "  [limpo]    %s\n" "$rotulo"
  else
    printf "  [SOBROU]   %s: %s\n" "$rotulo" "$achado"
    pendencias=$((pendencias + 1))
  fi
}

confere "stack" "$(aws cloudformation describe-stacks --region "$REGIAO" \
  --stack-name "$STACK" --query "Stacks[0].StackName" --output text 2>/dev/null || true)"
confere "bucket" "$(aws s3api head-bucket --bucket "$BUCKET" --region "$REGIAO" \
  2>/dev/null && echo "$BUCKET" || true)"
confere "database" "$(aws glue get-database --name "$DATABASE" --region "$REGIAO" \
  --query "Database.Name" --output text 2>/dev/null || true)"
confere "tabela" "$(aws glue get-table --database-name "$DATABASE" --name corridas \
  --region "$REGIAO" --query "Table.Name" --output text 2>/dev/null || true)"
confere "workgroup" "$(aws athena list-work-groups --region "$REGIAO" \
  --query "WorkGroups[?Name=='${WORKGROUP}'].Name" --output text 2>/dev/null || true)"

echo
if [[ "$pendencias" -eq 0 ]]; then
  echo "conta limpa: nenhum recurso desta stack sobrou."
else
  echo "ATENCAO: ${pendencias} recurso(s) sobraram - o criterio 5 cai inteiro." >&2
  exit 1
fi
