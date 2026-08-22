#!/usr/bin/env bash
# Verificacao do Exercicio 01. Roda na SUA conta e imprime PASSA/FALHA por
# criterio da rubrica. Rode antes de entregar: a nota nao e surpresa.
#
#   ./verificacao/verifica.sh <seu-login>                 # criterios 0 a 4
#   ./verificacao/verifica.sh <seu-login> --pos-destroy   # criterio 5
#
# O criterio 6 (DECISOES.md) e lido por uma pessoa e nao entra aqui.
set -uo pipefail

REGIAO="us-east-1"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
LOGIN="${1:-}"
MODO="${2:-}"

if [[ ! "$LOGIN" =~ ^[a-z0-9][a-z0-9-]{2,28}$ ]]; then
  echo "uso: ./verificacao/verifica.sh <seu-login> [--pos-destroy]" >&2
  exit 2
fi

STACK="eda-a04-${LOGIN}"
BUCKET="eda-a04-lake-${LOGIN}"
DATABASE="eda_a04_raw_${LOGIN}"
WORKGROUP="eda-a04-wg-${LOGIN}"
TEMPLATE="${RAIZ}/infra/template.yaml"

falhas=0
evidencia=""

ok()   { printf "  [PASSA]   %s\n" "$1"; evidencia+="[PASSA]   $1"$'\n'; }
nao()  { printf "  [FALHA]   %s\n" "$1"; evidencia+="[FALHA]   $1"$'\n'; falhas=$((falhas+1)); }
info() { printf "            %s\n" "$1"; evidencia+="          $1"$'\n'; }

saida() {
  aws cloudformation describe-stacks --region "$REGIAO" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null || true
}

echo "verificacao do Exercicio 01 · login ${LOGIN} · regiao ${REGIAO}"
echo

# ---------------------------------------------------------------- criterio 5
if [[ "$MODO" == "--pos-destroy" ]]; then
  echo "CRITERIO 5 - destroy limpo (15%)"
  sobrou=""
  [[ -n "$(aws cloudformation describe-stacks --region "$REGIAO" --stack-name "$STACK" \
      --query "Stacks[0].StackName" --output text 2>/dev/null || true)" ]] && sobrou+="stack "
  aws s3api head-bucket --bucket "$BUCKET" --region "$REGIAO" 2>/dev/null && sobrou+="bucket "
  [[ -n "$(aws glue get-database --name "$DATABASE" --region "$REGIAO" \
      --query "Database.Name" --output text 2>/dev/null || true)" ]] && sobrou+="database "
  [[ -n "$(aws athena list-work-groups --region "$REGIAO" \
      --query "WorkGroups[?Name=='${WORKGROUP}'].Name" --output text 2>/dev/null || true)" ]] && sobrou+="workgroup "
  if [[ -z "$sobrou" ]]; then
    ok "nenhum recurso orfao"
  else
    nao "sobraram: ${sobrou}"
  fi
  echo
  echo "----- cole no PR a partir daqui -----"
  printf "%s" "$evidencia"
  echo "-------------------------------------"
  exit $(( falhas > 0 ? 1 : 0 ))
fi

# ---------------------------------------------------------------- criterio 0
echo "CRITERIO 0 - sem Crawler (elimina)"
if [[ ! -f "$TEMPLATE" ]]; then
  nao "infra/template.yaml nao encontrado"
elif grep -q "AWS::Glue::Crawler" "$TEMPLATE"; then
  nao "existe AWS::Glue::Crawler no template - esta e a entrega da Aula 03"
  echo
  echo "criterio eliminatorio: a verificacao para aqui."
  exit 1
elif ! grep -q "AWS::Glue::Table" "$TEMPLATE"; then
  nao "nao existe AWS::Glue::Table no template"
  exit 1
else
  ok "nenhum Crawler, e ha AWS::Glue::Table"
fi
echo

# ---------------------------------------------------------------- criterio 1
echo "CRITERIO 1 - os cinco outputs de contrato (10%)"
faltando=""
for o in BucketName DatabaseName TableName WorkGroupName TetoBytes; do
  v="$(saida "$o")"
  if [[ -z "$v" || "$v" == "None" ]]; then faltando+="$o "; else info "$o = $v"; fi
done
if [[ -z "$faltando" ]]; then ok "os cinco existem e estao preenchidos"
else nao "faltam ou estao vazios: ${faltando}"; fi
echo

TETO="$(saida TetoBytes)"

# ---------------------------------------------------------------- criterio 2
echo "CRITERIO 2 - schema declarado (25%)"
tabela="$(aws glue get-table --database-name "$DATABASE" --name corridas \
  --region "$REGIAO" --output json 2>/dev/null || true)"
if [[ -z "$tabela" ]]; then
  nao "a tabela corridas nao existe em ${DATABASE}"
else
  ncol="$(printf '%s' "$tabela" | python3 -c "import json,sys;print(len(json.load(sys.stdin)['Table']['StorageDescriptor']['Columns']))")"
  chave="$(printf '%s' "$tabela" | python3 -c "import json,sys;k=json.load(sys.stdin)['Table'].get('PartitionKeys',[]);print(','.join(c['Name'] for c in k))")"
  info "colunas declaradas: ${ncol}"
  info "chave de particao: ${chave:-nenhuma}"
  if [[ "$ncol" -ge 8 && "$chave" == "dt" ]]; then
    ok "≥ 8 colunas e chave de particao dt"
  else
    nao "exige ≥ 8 colunas (tem ${ncol}) e chave dt (tem '${chave}')"
  fi
  tipo_valor="$(printf '%s' "$tabela" | python3 -c "
import json,sys
c=[x for x in json.load(sys.stdin)['Table']['StorageDescriptor']['Columns'] if x['Name']=='valor']
print(c[0]['Type'] if c else 'ausente')")"
  info "valor foi declarado como: ${tipo_valor}  (DECISAO 01 - justifique)"
fi
echo

# ---------------------------------------------------------------- criterio 3
echo "CRITERIO 3 - particoes declaradas (15%)"
HOJE="$(python3 -c "import datetime as d;print(d.date.today().isoformat())")"
parts="$(aws glue get-partitions --database-name "$DATABASE" --table-name corridas \
  --region "$REGIAO" --output json 2>/dev/null || true)"
if [[ -z "$parts" ]]; then
  nao "nenhuma particao registrada"
else
  npart="$(printf '%s' "$parts" | python3 -c "import json,sys;print(len(json.load(sys.stdin)['Partitions']))")"
  temhoje="$(printf '%s' "$parts" | python3 -c "
import json,sys
p=json.load(sys.stdin)['Partitions']
print('sim' if any('${HOJE}' in x['Values'] for x in p) else 'nao')")"
  info "particoes registradas: ${npart}"
  info "a particao de hoje (${HOJE}) esta declarada: ${temhoje}"
  if [[ "$npart" -ge 3 && "$temhoje" == "sim" ]]; then
    ok "≥ 3 particoes, e a de hoje esta entre elas"
  else
    nao "exige ≥ 3 particoes (tem ${npart}) com a de hoje incluida (${temhoje})"
  fi
  # Location que nao bate com a chave real devolve zero linha e nenhum erro.
  ruins="$(printf '%s' "$parts" | python3 -c "
import json,sys
p=json.load(sys.stdin)['Partitions']
ruins=[x['Values'][0] for x in p
       if 'dt='+x['Values'][0] not in x['StorageDescriptor']['Location']]
print(' '.join(ruins))")"
  if [[ -n "$ruins" ]]; then
    nao "Location nao bate com a chave nestas particoes: ${ruins}"
    info "o Athena devolveria zero linha, sem erro nenhum"
  else
    ok "todo Location bate com a chave dt= do objeto"
  fi
fi
echo

# ---------------------------------------------------------------- criterio 4
echo "CRITERIO 4 - o teto mata a larga e deixa passar a estreita (15%)"
consulta() {
  local sql="$1"
  local qid
  qid="$(aws athena start-query-execution --region "$REGIAO" \
    --work-group "$WORKGROUP" \
    --query-execution-context "Database=${DATABASE}" \
    --query-string "$sql" --query QueryExecutionId --output text 2>/dev/null || true)"
  [[ -z "$qid" ]] && { echo "ERRO|0"; return; }
  for _ in $(seq 1 40); do
    local est
    est="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
      --query "QueryExecution.Status.State" --output text 2>/dev/null || echo ERRO)"
    case "$est" in
      SUCCEEDED|FAILED|CANCELLED)
        local bytes
        bytes="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
          --query "QueryExecution.Statistics.DataScannedInBytes" --output text 2>/dev/null || echo 0)"
        echo "${est}|${bytes}"; return;;
    esac
    sleep 3
  done
  echo "TIMEOUT|0"
}

larga="$(consulta "SELECT count(*) FROM corridas;")"
estreita="$(consulta "SELECT count(*) FROM corridas WHERE dt = '${HOJE}';")"
info "consulta larga   (sem WHERE dt): ${larga%%|*} · ${larga##*|} bytes"
info "consulta estreita (com WHERE dt): ${estreita%%|*} · ${estreita##*|} bytes"
info "teto declarado: ${TETO} bytes"

if [[ "${larga%%|*}" == "FAILED" && "${estreita%%|*}" == "SUCCEEDED" ]]; then
  ok "o freio tocou na larga e deixou a estreita passar"
elif [[ "${larga%%|*}" == "SUCCEEDED" ]]; then
  nao "a consulta larga passou - o teto esta alto demais para ser sentido"
else
  nao "a consulta estreita nao respondeu - confira Location e particoes"
fi
echo

# ---------------------------------------------------------------- criterio 6
echo "CRITERIO 6 - DECISOES.md (20%)"
DEC="${RAIZ}/DECISOES.md"
if [[ ! -f "$DEC" ]]; then
  nao "DECISOES.md nao existe na raiz do pacote"
else
  n="$(grep -c -E '^\s*(#+\s*)?DECIS(A|Ã)O\s*0[1-5]' "$DEC" || true)"
  info "decisoes encontradas no arquivo: ${n} de 5"
  if [[ "$n" -ge 5 ]]; then ok "as cinco decisoes aparecem (o texto e lido por uma pessoa)"
  else nao "faltam decisoes: o criterio exige uma frase por decisao"; fi
fi

echo
echo "----- cole no PR a partir daqui -----"
printf "%s" "$evidencia"
echo "resumo: ${falhas} criterio(s) em FALHA"
echo "-------------------------------------"
exit $(( falhas > 0 ? 1 : 0 ))
