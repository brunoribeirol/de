#!/usr/bin/env bash
# =============================================================================
# measure-run.sh — the numbers behind DECISOES.md (Exercício 05), after ONE job run.
#
# verifica.sh says PASSA/FALHA; this script records what the table looks like
# after each run, so DECISOES.md can compare run 1, run 2 and the backfill with
# the same five numbers:
#   - the dates the raw implies (HOJE = last raw folder, D-3, D-5, DESDE);
#   - the 7-day night count (the dashboard question) and total vs distinct rows;
#   - rows per event day for the last 7 days (where a hole would show);
#   - the Parquet files under dt=D-3 and dt=HOJE, with their timestamps (append
#     leaves one file per run, sobrescrever replaces it);
#   - the job report the last run wrote (relatorios/corridas.json).
# Read-only except for the Athena queries it runs (~10 MB scanned each).
#
#   ./verification/measure-run.sh 2>&1 | tee docs/evidence/measure-after-run-1.txt
#
# Dates come from the raw folders, not the clock, exactly as verifica.sh does,
# so it gives the same answer before and after midnight.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
out() { terraform -chdir=terraform output -raw "$1"; }
BUCKET="$(out bucket)"; DB="$(out database)"; WG="$(out workgroup)"; TABLE="$(out tabela)"

HOJE=$(aws s3 ls "s3://$BUCKET/raw/corridas/" | awk '{print $2}' | sed -n 's#^dt=\(.*\)/$#\1#p' | sort | tail -1)
[[ -n "$HOJE" ]] || { echo "raw is empty: load it first" >&2; exit 2; }
minus() { python3 -c 'import datetime as d, sys; print(d.date.fromisoformat(sys.argv[1]) - d.timedelta(days=int(sys.argv[2])))' "$HOJE" "$1"; }
D3="$(minus 3)"; D5="$(minus 5)"; DESDE="$(minus 6)"

# Runs one query in the group's workgroup; prints every result row (header
# skipped), tab-separated. Prints the failure reason and returns 1 on error.
athena() {
  local qid state
  qid="$(aws athena start-query-execution --work-group "$WG" --query-execution-context "Database=$DB" \
         --query-string "$1" --query QueryExecutionId --output text)"
  while true; do
    state="$(aws athena get-query-execution --query-execution-id "$qid" \
             --query QueryExecution.Status.State --output text)"
    case "$state" in
      SUCCEEDED) break ;;
      FAILED|CANCELLED)
        echo "athena $state: $(aws athena get-query-execution --query-execution-id "$qid" \
              --query QueryExecution.Status.StateChangeReason --output text)" >&2
        return 1 ;;
    esac
    sleep 2
  done
  aws athena get-query-results --query-execution-id "$qid" \
    --query 'ResultSet.Rows[1:].Data[*].VarCharValue' --output text
}

echo "== $(date '+%Y-%m-%d %H:%M:%S %Z') · table $DB.$TABLE · decisions $(terraform -chdir=terraform output -json decisoes | tr -d ' \n')"
echo "== dates from the raw: hoje=$HOJE  d-3=$D3  d-5=$D5  desde=$DESDE"
echo
echo "night, last 7 days (dt >= '$DESDE' AND faixa_hora BETWEEN 0 AND 5): $(athena \
  "SELECT count(*) FROM $TABLE WHERE dt >= '$DESDE' AND faixa_hora BETWEEN 0 AND 5")"
read -r rows distinct <<<"$(athena "SELECT count(*), count(DISTINCT corrida_id) FROM $TABLE")"
echo "table: $rows rows, $distinct distinct corrida_id"
echo
echo "rows per event day, last 7 days (dt · rows · night rows):"
athena "SELECT dt, count(*), count_if(faixa_hora BETWEEN 0 AND 5) FROM $TABLE
        WHERE dt >= '$DESDE' GROUP BY dt ORDER BY dt" | sed 's/^/  /'
echo
echo "Parquet files (one per run under append; replaced under sobrescrever):"
for d in "$D5" "$D3" "$HOJE"; do
  aws s3 ls "s3://$BUCKET/trusted/$TABLE/dt=$d/" | sed "s#^#  dt=$d  #"
done
aws s3 ls "s3://$BUCKET/trusted/$TABLE/" --recursive --summarize | tail -2 | sed 's/^ */  /'
echo
echo "last job report (s3://$BUCKET/relatorios/$TABLE.json):"
aws s3 cp "s3://$BUCKET/relatorios/$TABLE.json" - | sed 's/^/  /'
