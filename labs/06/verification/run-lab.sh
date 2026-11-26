#!/usr/bin/env bash
# Exercício 06 (Aula 29) — run: LF settings backup -> init -> plan (guard 32) -> apply ->
# load raw -> both jobs -> ask as each profile -> new-table probe -> course verifier.
# The destroy is a separate script, run only after the evidence is checked.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-de}"
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""
LAB="$(cd "$(dirname "$0")/.." && pwd)"
EV="$LAB/docs/evidence"
PRIV="$LAB/.private"          # gitignored: account-identifying files
mkdir -p "$EV" "$PRIV"
cd "$LAB"

step() { printf '\n==== %s  %s\n' "$(date +%H:%M:%S)" "$*"; }
# Keep the 12-digit account id out of the evidence (not other numbers).
red() { sed -l -E 's/(^|[^0-9])[0-9]{12}([^0-9]|$)/\1<account>\2/g; s/(^|[^0-9])[0-9]{12}([^0-9]|$)/\1<account>\2/g'; }

step "0. who is running (terminal only, not saved in the repo)"
aws sts get-caller-identity --query Arn --output text
read -r -p "Is this the group account (profile $AWS_PROFILE)? Enter to go on, Ctrl-C to stop. " _

step "1. save the account's Lake Formation settings before Terraform replaces them"
if [[ -f "$PRIV/lf-settings-before.json" ]]; then
  echo "backup already exists (a previous run): kept as is"
else
  aws lakeformation get-data-lake-settings --output json > "$PRIV/lf-settings-before.json"
fi
python3 -I - "$PRIV/lf-settings-before.json" <<'PY' 2>&1 | tee "$EV/lf-settings-before.txt"
import json, sys
s = json.load(open(sys.argv[1]))["DataLakeSettings"]
def who(lst): return [p["Principal"]["DataLakePrincipalIdentifier"].split(":")[-1] if ":" in p["Principal"]["DataLakePrincipalIdentifier"] else p["Principal"]["DataLakePrincipalIdentifier"] for p in lst]
print("Lake Formation settings BEFORE the apply (account id omitted)")
print("  admins:", len(s.get("DataLakeAdmins", [])), [a["DataLakePrincipalIdentifier"].split(":")[-1] for a in s.get("DataLakeAdmins", [])])
print("  default permissions on new databases:", who(s.get("CreateDatabaseDefaultPermissions", [])))
print("  default permissions on new tables:   ", who(s.get("CreateTableDefaultPermissions", [])))
PY

step "2. init (remote backend of the group, key aula29/grupo07)"
terraform -chdir=terraform init -input=false -no-color -backend-config=backend.hcl 2>&1 | red | tee "$EV/init.txt"

step "3. plan (must be 32 to add, 0 to change, 0 to destroy)"
terraform -chdir=terraform plan -input=false -no-color -out=lab06.tfplan 2>&1 | red | tee "$EV/plan.txt"
grep -q 'Plan: 32 to add, 0 to change, 0 to destroy' "$EV/plan.txt" \
  || { echo "STOP: the plan is not 32/0/0 — nothing applied"; exit 1; }

step "4. apply"
terraform -chdir=terraform apply -input=false -no-color lab06.tfplan 2>&1 | red | tee "$EV/apply.txt"

step "5. load the raw (30 days + the two planted problems)"
./carregar-raw.sh 2>&1 | red | tee "$EV/load-raw.txt"
HOJE=$(sed -n 's/^hoje=\([0-9-]*\).*/\1/p' "$EV/load-raw.txt")
DESDE=$(sed -n 's/.*desde=\([0-9-]*\).*/\1/p' "$EV/load-raw.txt")
echo "HOJE=$HOJE DESDE=$DESDE"

step "6. both jobs (raw -> trusted -> refined, ~5 min)"
./rodar-jobs.sh 2>&1 | red | tee "$EV/jobs-run-1.txt"
if ! grep -q '"linhas_na_tabela": 660' "$EV/jobs-run-1.txt"; then
  echo "refined is not 660 rows: re-running only the refined job (it overwrites)"
  ./rodar-jobs.sh refined 2>&1 | red | tee "$EV/jobs-run-2-refined.txt"
fi

REF=eda_a29_grupo07_refined; TRU=eda_a29_grupo07_trusted; RAW=eda_a29_grupo07_raw
probe() { printf '\n--- as %s: %s\n' "$1" "$2"; ./como.sh "$1" "$2" || true; }

step "7. ask as each profile"
{
  echo "today=$HOJE since=$DESDE"
  probe prefeitura "SELECT sum(corridas) FROM $REF.madrugada_bairro WHERE dt >= '$DESDE'"
  probe prefeitura "SELECT count(*) AS linhas, count(DISTINCT bairro) AS bairros, count(DISTINCT dt) AS dias FROM $REF.madrugada_bairro"
  probe prefeitura "SELECT count(*) FROM $TRU.corridas WHERE dt = '$HOJE'"
  probe prefeitura "SELECT count(*) FROM $RAW.corridas WHERE dt = '$HOJE'"
  probe analista   "SELECT count(bairro) FROM $TRU.corridas"
  probe analista   "SELECT count(DISTINCT corrida_id) FROM $TRU.corridas"
  probe analista   "SELECT * FROM $TRU.corridas WHERE dt = '$HOJE' LIMIT 1"
  probe analista   "SELECT passageiro_id FROM $TRU.corridas WHERE dt = '$HOJE' LIMIT 1"
  probe analista   "SELECT motorista_id FROM $TRU.corridas WHERE dt = '$HOJE' LIMIT 1"
  probe analista   "SELECT sum(corridas) FROM $REF.madrugada_bairro WHERE dt >= '$DESDE'"
} 2>&1 | red | tee "$EV/profiles.txt"

step "8. DECISÃO 01 probe: a NEW table in the refined, created after the grants"
python3 -I - "$PRIV/probe-table.json" <<'PY'
import json, sys
proj = {"projection.enabled": "true", "projection.dt.type": "date", "projection.dt.format": "yyyy-MM-dd",
        "projection.dt.range": "NOW-60DAYS,NOW+1DAYS", "projection.dt.interval": "1",
        "projection.dt.interval.unit": "DAYS", "classification": "parquet",
        "storage.location.template": "s3://eda-a29-lake-grupo07/refined/madrugada_bairro/dt=${dt}/"}
t = {"Name": "sonda_tabela_nova", "TableType": "EXTERNAL_TABLE", "Parameters": proj,
     "PartitionKeys": [{"Name": "dt", "Type": "string"}],
     "StorageDescriptor": {"Location": "s3://eda-a29-lake-grupo07/refined/madrugada_bairro/",
        "Columns": [{"Name": "bairro", "Type": "string"}, {"Name": "corridas", "Type": "bigint"}, {"Name": "receita", "Type": "double"}],
        "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
        "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
        "SerdeInfo": {"SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"}}}
json.dump(t, open(sys.argv[1], "w"))
PY
aws glue create-table --database-name "$REF" --table-input "file://$PRIV/probe-table.json"
{
  echo "sonda_tabela_nova: created in $REF after terraform apply, same files as madrugada_bairro"
  probe prefeitura "SELECT sum(corridas) FROM $REF.sonda_tabela_nova WHERE dt >= '$DESDE'"
  probe analista   "SELECT sum(corridas) FROM $REF.sonda_tabela_nova WHERE dt >= '$DESDE'"
} 2>&1 | red | tee "$EV/probe-new-refined-table.txt"
aws glue delete-table --database-name "$REF" --name sonda_tabela_nova
echo "sonda_tabela_nova deleted" | tee -a "$EV/probe-new-refined-table.txt"

step "9. the contract as a consumer reads it in the catalog"
aws glue get-table --database-name "$REF" --name madrugada_bairro --output json \
  --query 'Table.{Description:Description,Parameters:Parameters,Columns:StorageDescriptor.Columns,PartitionKeys:PartitionKeys}' \
  2>&1 | red | tee "$EV/catalog-contract.json"

step "10. course verifier (criteria 0-4)"
./verification/verifica.sh 2>&1 | red | tee "$EV/verification-before-destroy.txt"

step "done — read docs/evidence/, then run verification/teardown.sh"
