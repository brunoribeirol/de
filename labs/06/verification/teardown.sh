#!/usr/bin/env bash
# Exercício 06 (Aula 29) — teardown: terraform destroy -> course check (criterion 5) ->
# restore the account's Lake Formation settings saved before the apply -> state check.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-de}"
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""
LAB="$(cd "$(dirname "$0")/.." && pwd)"
EV="$LAB/docs/evidence"
PRIV="$LAB/.private"
cd "$LAB"
step() { printf '\n==== %s  %s\n' "$(date +%H:%M:%S)" "$*"; }
red() { sed -l -E 's/(^|[^0-9])[0-9]{12}([^0-9]|$)/\1<account>\2/g; s/(^|[^0-9])[0-9]{12}([^0-9]|$)/\1<account>\2/g'; }
[[ -f "$PRIV/lf-settings-before.json" ]] || { echo "STOP: no Lake Formation backup in $PRIV"; exit 1; }

step "1. take the account-wide Lake Formation settings out of the state (shared account)"
# Destroying aws_lakeformation_data_lake_settings empties the account's admin list and default
# permissions — every group's, not ours. Record which admins OUR apply set, then forget the
# resource, so the destroy leaves the account settings alone; step 4 puts back the old admins.
if terraform -chdir=terraform state list | grep -qx 'aws_lakeformation_data_lake_settings.conta'; then
  terraform -chdir=terraform state pull | python3 -I -c '
import json, sys
s = json.load(sys.stdin)
r = [x for x in s["resources"] if x["type"] == "aws_lakeformation_data_lake_settings"][0]
json.dump(r["instances"][0]["attributes"]["admins"], open(sys.argv[1], "w"))' "$PRIV/our-admins.json"
  terraform -chdir=terraform state rm -no-color aws_lakeformation_data_lake_settings.conta 2>&1 | red | tee "$EV/state-rm-lf-settings.txt"
else
  echo "settings already out of the state"
fi
[[ -f "$PRIV/our-admins.json" ]] || { echo "STOP: no record of the admins our apply set"; exit 1; }

step "2. destroy (31 resources: the 32 minus the account settings)"
terraform -chdir=terraform destroy -input=false -no-color -auto-approve 2>&1 | red | tee "$EV/destroy.txt"

step "2. course check after destroy (criterion 5)"
./verification/verifica.sh --pos-destroy 2>&1 | red | tee "$EV/post-destroy-verification.txt"

step "2b. independent check: print each service's own answer (the course check hides errors)"
{
  aws s3api head-bucket --bucket eda-a29-lake-grupo07 2>&1 | tail -1 || true
  for c in raw trusted refined; do aws glue get-database --name "eda_a29_grupo07_$c" 2>&1 | tail -1 || true; done
  for j in trusted refined; do aws glue get-job --job-name "eda-a29-grupo07-$j" 2>&1 | tail -1 || true; done
  aws athena get-work-group --work-group eda-a29-grupo07-wg 2>&1 | tail -1 || true
  for p in glue lf prefeitura analista; do aws iam get-role --role-name "eda-a29-grupo07-$p" 2>&1 | tail -1 || true; done
  aws iam list-policies --scope Local --query "Policies[?PolicyName=='eda-a29-grupo07-consumo'].PolicyName" --output text 2>&1 || true
  echo "lake formation registrations for the bucket: [$(aws lakeformation list-resources --query "ResourceInfoList[?contains(ResourceArn, 'eda-a29-lake-grupo07')].ResourceArn" --output text 2>&1)]"
} 2>&1 | red | tee "$EV/manual-cleanup-check.txt"

step "3. give the account its Lake Formation admins back (merge, not overwrite)"
# admins = the ones before our apply + anyone another group added since, minus the ones our
# apply put in; default permissions for new databases/tables = as they were before our apply.
aws lakeformation get-data-lake-settings --output json > "$PRIV/lf-settings-now.json"
python3 -I - "$PRIV/lf-settings-before.json" "$PRIV/lf-settings-now.json" "$PRIV/our-admins.json" "$PRIV/lf-settings-restore-input.json" <<'PY'
import json, sys
before = json.load(open(sys.argv[1]))["DataLakeSettings"]
now = json.load(open(sys.argv[2]))["DataLakeSettings"]
ours = set(json.load(open(sys.argv[3])))
ids = lambda s: [a["DataLakePrincipalIdentifier"] for a in s.get("DataLakeAdmins", [])]
keep = ids(before) + [a for a in ids(now) if a not in ours and a not in ids(before)]
final = dict(now)
final["DataLakeAdmins"] = [{"DataLakePrincipalIdentifier": a} for a in keep]
for k in ("CreateDatabaseDefaultPermissions", "CreateTableDefaultPermissions"):
    final[k] = before.get(k, [])
json.dump(final, open(sys.argv[4], "w"))
PY
aws lakeformation put-data-lake-settings --data-lake-settings "file://$PRIV/lf-settings-restore-input.json"
aws lakeformation get-data-lake-settings --output json > "$PRIV/lf-settings-after.json"
python3 -I - "$PRIV/lf-settings-before.json" "$PRIV/lf-settings-after.json" <<'PY' 2>&1 | tee "$EV/lf-settings-restored.txt"
import json, sys
b, a = (json.load(open(f))["DataLakeSettings"] for f in sys.argv[1:3])
short = lambda s, k: sorted(x["DataLakePrincipalIdentifier"].split(":")[-1] for x in s.get(k, []))
perm = lambda s, k: sorted(x["Principal"]["DataLakePrincipalIdentifier"].split(":")[-1] for x in s.get(k, []))
print("admins before:", short(b, "DataLakeAdmins"))
print("admins after: ", short(a, "DataLakeAdmins"))
for k in ("CreateDatabaseDefaultPermissions", "CreateTableDefaultPermissions"):
    print(f"{k}: before={perm(b, k)} after={perm(a, k)}")
ok = set(short(b, "DataLakeAdmins")) <= set(short(a, "DataLakeAdmins")) and all(perm(b, k) == perm(a, k) for k in ("CreateDatabaseDefaultPermissions", "CreateTableDefaultPermissions"))
print("RESTORED (every admin from before is back; default permissions as before)" if ok else "DIFFERENT — check by hand")
PY

step "4. nothing left in the state"
{ echo "terraform state list (empty = nothing left):"; terraform -chdir=terraform state list 2>&1; echo "(end)"; } | red | tee "$EV/state-after-destroy.txt"
rm -rf /tmp/eda-a29
step "done"
