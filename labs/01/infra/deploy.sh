#!/usr/bin/env bash
# Sobe a sua stack do Exercicio 01. Rode SEMPRE da raiz do pacote.
#   ./infra/deploy.sh <seu-login>
set -euo pipefail

REGIAO="us-east-1"
AQUI="$(cd "$(dirname "$0")" && pwd)"
LOGIN="${1:-}"

if [[ ! "$LOGIN" =~ ^[a-z0-9][a-z0-9-]{2,28}$ ]]; then
  echo "uso: ./infra/deploy.sh <seu-login>     # minusculas, digitos e hifens" >&2
  echo "a conta e compartilhada: o sufixo e o SEU login, nao a turma." >&2
  exit 1
fi

# Le os tres parametros do parameters.json. Os placeholders sao recusados pelo
# AllowedPattern do template - a stack nao sobe pela metade.
ler() {
  python3 -c "
import json,sys
p=json.load(open('$AQUI/parameters.json'))
v=[x['ParameterValue'] for x in p if x['ParameterKey']=='$1']
print(v[0] if v else '')
"
}
TURMA="$(ler Turma)"
OWNER="$(ler Owner)"
TETO="$(ler TetoBytesPorConsulta)"

# As datas sao calculadas na hora, nunca versionadas: a janela do gerador
# termina sempre hoje. python3 porque o `date` do macOS e o do Linux divergem.
data() { python3 -c "import datetime as d;print((d.date.today()-d.timedelta(days=$1)).isoformat())"; }
D1="$(data 2)"; D2="$(data 1)"; D3="$(data 0)"

STACK="eda-a04-${LOGIN}"
echo "regiao ${REGIAO} · login ${LOGIN} · particoes ${D1} ${D2} ${D3}"

aws cloudformation deploy \
  --region "$REGIAO" \
  --stack-name "$STACK" \
  --template-file "$AQUI/template.yaml" \
  --parameter-overrides \
      "Turma=${TURMA}" "Sufixo=${LOGIN}" "Owner=${OWNER}" \
      "TetoBytesPorConsulta=${TETO}" \
      "DataParticao1=${D1}" "DataParticao2=${D2}" "DataParticao3=${D3}" \
  --tags Disciplina=EDA Aula=04 "Turma=${TURMA}" "Owner=${OWNER}"

echo
aws cloudformation describe-stacks --region "$REGIAO" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table

saida() {
  aws cloudformation describe-stacks --region "$REGIAO" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

echo
echo "copie e cole as seis linhas abaixo - o roteiro e o verifica.sh usam todas:"
echo
echo "export STACK=${STACK}"
echo "export BUCKET=$(saida BucketName)"
echo "export DATABASE=$(saida DatabaseName)"
echo "export TABELA=$(saida TableName)"
echo "export WORKGROUP=$(saida WorkGroupName)"
echo "export DT=${D3}"
