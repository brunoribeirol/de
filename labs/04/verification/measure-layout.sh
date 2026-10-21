#!/usr/bin/env bash
# =============================================================================
# measure-layout.sh — the measured numbers behind DECISOES.md (Exercício 04).
#
# verifica.sh says PASSA/FALHA; this script records WHY, one number per
# decision: files the 7-day question opens, file and footer sizes, bytes the
# question scans, what the workgroup cutoff lets through and what it blocks,
# and how many partitions the catalog holds. Read-only except for the Athena
# queries it runs (a few MB scanned in total).
#
#   ./verification/measure-layout.sh | tee docs/evidence/measure-layout.txt
#
# Run from the lab root, after rodar-job.sh, on the same local day as
# carregar-raw.sh (the 7-day window is computed from today's date).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
REGION="${AWS_REGION:-us-east-1}"
out() { terraform -chdir=terraform output -raw "$1"; }
BUCKET="$(out bucket_name)"; DB="$(out database_name)"; TABLE="$(out trusted_table_name)"
WG="$(out workgroup_name)"; CUTOFF="$(out teto_bytes)"; TARGET="$(out meta_bytes_madrugada)"
SINCE="$(python3 -c 'import datetime as d; print(d.date.today() - d.timedelta(days=6))')"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Runs a query in the group's workgroup. Prints: STATE BYTES QID
athena() {
  local qid state
  qid="$(aws athena start-query-execution --work-group "$WG" --region "$REGION" \
         --query-string "$1" --query QueryExecutionId --output text)"
  while true; do
    state="$(aws athena get-query-execution --query-execution-id "$qid" --region "$REGION" \
             --query QueryExecution.Status.State --output text)"
    case "$state" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
    sleep 2
  done
  echo "$state $(aws athena get-query-execution --query-execution-id "$qid" --region "$REGION" \
                 --query QueryExecution.Statistics.DataScannedInBytes --output text) $qid"
}
reason() { aws athena get-query-execution --query-execution-id "$1" --region "$REGION" \
             --query QueryExecution.Status.StateChangeReason --output text | cut -c1-120; }

echo "== layout: $(out chaves_particao) · window: dt >= $SINCE · cutoff: $CUTOFF · target: $TARGET"

# ---------------------------------------------------------------- S3 (01, 02)
aws s3api list-objects-v2 --bucket "$BUCKET" --prefix trusted/corridas/ --region "$REGION" \
  --query 'Contents[?ends_with(Key, `.parquet`)].[Key,Size]' --output text > "$TMP/files.tsv"
awk -F'\t' '{d=$1; sub(/\/[^\/]*$/, "", d); n[d]++; s+=$2; f++}
     END {m=0; for (k in n) if (n[k] > m) m = n[k];
          printf "trusted: %d files in %d folders, max %d per folder, %d bytes, avg %d bytes/file\n",
                 f, length(n), m, s, s/f}' "$TMP/files.tsv"

# The files the 7-day question can open: every folder with dt >= SINCE.
awk -F'\t' -v since="$SINCE" 'match($1, /dt=[0-9-]+/) && substr($1, RSTART+3, 10) >= since' \
  "$TMP/files.tsv" > "$TMP/window.tsv"
echo "7-day window: $(wc -l < "$TMP/window.tsv" | tr -d ' ') files"

# Parquet ends with <4-byte little-endian footer length><"PAR1">.
footer_total=0
while IFS=$'\t' read -r key size; do
  aws s3api get-object --bucket "$BUCKET" --key "$key" --range bytes=-8 --region "$REGION" \
    "$TMP/tail" > /dev/null
  footer="$(python3 -I -c 'import struct,sys
d = open(sys.argv[1], "rb").read()
assert d[4:] == b"PAR1", "not a Parquet file"
print(struct.unpack("<I", d[:4])[0])' "$TMP/tail")"
  footer_total=$((footer_total + footer))
  printf "  %-60s %9d bytes  footer %6d bytes\n" "${key#trusted/corridas/}" "$size" "$footer"
done < "$TMP/window.tsv"
echo "footers in the window: $footer_total bytes"

# ------------------------------------------------------------- Athena (03, 04)
read -r S1 B1 Q1 <<<"$(athena "SELECT bairro, count(*) AS corridas, round(sum(valor), 2) AS receita FROM $DB.$TABLE WHERE dt >= '$SINCE' AND faixa_hora BETWEEN 0 AND 5 GROUP BY bairro")"
RIDES="$(aws athena get-query-results --query-execution-id "$Q1" --region "$REGION" \
          --query 'ResultSet.Rows[1:].Data[*].VarCharValue' --output text | awk '{s+=$(NF-1)} END{print s+0}')"
echo "night question (7 days): $S1 · scanned $B1 bytes · $RIDES rides · target $TARGET ($((B1 * 100 / TARGET))% of it)"

WIDE="max(corrida_id), max(motorista_id), max(passageiro_id), max(inicio), max(fim), max(distancia_km), max(duracao_min), max(valor)"
read -r S2 B2 Q2 <<<"$(athena "SELECT $WIDE FROM $DB.$TABLE WHERE dt >= '$SINCE'")"
echo "all columns, 7 days:  $S2 · scanned $B2 bytes"
read -r S3 B3 Q3 <<<"$(athena "SELECT $WIDE FROM $DB.$TABLE")"
echo "all columns, 30 days: $S3 · scanned $B3 bytes before stopping"
if [ "$S3" != "SUCCEEDED" ]; then echo "  reason: $(reason "$Q3")"; fi

# ----------------------------------------------------------------- catalog (05)
echo "partitions in the Glue catalog: $(aws glue get-partitions --database-name "$DB" --table-name "$TABLE" \
        --region "$REGION" --query 'length(Partitions)' --output text)"
echo "projection.dt.range: $(aws glue get-table --database-name "$DB" --name "$TABLE" --region "$REGION" \
        --query 'Table.Parameters."projection.dt.range"' --output text)"
echo "measured at: $(date -u +%FT%TZ)"
