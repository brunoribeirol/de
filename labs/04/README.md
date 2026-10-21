# Lab 04 (Exercício 04, Aula 21) — A cost target in partitioned Parquet

The startup's `trusted` table, rewritten as **partitioned Parquet** in Terraform
(remote backend, group account), with one new requirement: before measuring, the
group **declares how many bytes the "night question" may scan** — at most 1 MiB —
and Athena proves or disproves it. It is the first increment of Project Part 2:
this `trusted` is the one AV2 grades.

The night question, fixed for the whole cycle:

```sql
SELECT bairro, count(*) AS corridas, round(sum(valor), 2) AS receita
FROM eda_a21_<suffix>.trusted_corridas
WHERE dt >= '<today - 6>' AND faixa_hora BETWEEN 0 AND 5
GROUP BY bairro;   -- 22 rows, 11,137 rides
```

## Assignment in short

- the `trusted` table is declared as Parquet, partitioned with `dt` first, all 10 columns;
- 518,400 rides over 30 days, at most 4 files per partition folder;
- a cost target ≤ 1 MiB that the 7-day night question stays under, with the right answer;
- a WorkGroup cutoff, enforced, that blocks the query reading every column;
- clean `destroy` of every `eda-a21-*` resource; `DECISOES.md` with one measured number per decision.

## What was decided

Full reasoning and numbers in [`DECISOES.md`](DECISOES.md).

| # | Decision | Choice | Why, in one line |
|---|---|---|---|
| 01 | Partition key | `["dt"]` | the question filters by date and only groups by bairro: 7 files opened, not 154 |
| 02 | Files per folder | `1` | a whole day is ~600 KB of Parquet; every extra file is one more footer and S3 request |
| 03 | Cost target | `524288` (512 KiB) | Lab 05 measured ≈ 0.4 MB for the same data and layout, plus ~25% headroom |
| 04 | WorkGroup cutoff | `10485760` (10 MiB) | the tightest cutoff Athena accepts; passes a full-width week, blocks a full-width month |
| 05 | Partition registration | partition projection, `2026-01-01,NOW` | new days appear with no command; fixed start avoids the UTC-vs-local window trap |

Only two places in the course's starting point were changed: the three Parquet
lines of `aws_glue_catalog_table.trusted` and `local.projecao` in
[`terraform/main.tf`](terraform/main.tf). The layout reaches the Glue job as job
arguments declared in Terraform, so the PySpark script is untouched.

## Layout

```
labs/04/
├── DECISOES.md                    decisions 01–05, each with a measured number
├── carregar-raw.sh                course · generates 30 days (seed 42) and uploads the raw layer
├── rodar-job.sh                   course · runs the Glue job; runs MSCK only if projection is off
├── app/gerador-eventos.py         course · deterministic ride generator
├── terraform/
│   ├── main.tf                    the 11 resources (Parquet lines + projection are ours)
│   ├── scripts/trusted-parquet.py course · the PySpark job
│   ├── backend.hcl.example        template — backend.hcl is gitignored
│   └── terraform.tfvars.example   the four decision values — terraform.tfvars is gitignored
├── verification/
│   ├── verifica.sh                course · acceptance criteria 0–6
│   └── measure-layout.sh          ours · the number behind each decision
└── docs/evidence/                 raw output of every step
```

`app/` and the two root scripts keep the course package's names because the
scripts `cd` to their own folder and call `app/` and `terraform -chdir=terraform`.
The course's `verificacao/` became `verification/`, as in Labs 01–03; the
verifier locates the lab root from its own path, so nothing else changed.

## Run it

All commands from `labs/04/`. The state bucket must exist first — see
[`infra/tfstate-backend/`](../../infra/tfstate-backend/).

```bash
cp terraform/backend.hcl.example terraform/backend.hcl          # bucket/key: the group's
cp terraform/terraform.tfvars.example terraform/terraform.tfvars  # turma, owner, sufixo

terraform -chdir=terraform init -backend-config=backend.hcl
terraform -chdir=terraform plan -out=lab04.tfplan                 # 11 to add
terraform -chdir=terraform apply lab04.tfplan
./carregar-raw.sh                                                 # 30 objects, 117,655,606 bytes
./rodar-job.sh                                                    # SUCCEEDED, 518,400 rows
./verification/verifica.sh                                        # criteria 0–5
./verification/measure-layout.sh                                  # the numbers in DECISOES.md

terraform -chdir=terraform destroy
./verification/verifica.sh --pos-destroy                          # criterion 6
rm -rf /tmp/eda-a21
```

Load the raw layer and run the verifier **on the same local day**: the generator
ends its 30-day window on today's date and the verifier computes `today − 6` the
same way. A day boundary in between turns the expected 11,137 rides into 9,546
(1,591 night rides per day × 6).

On a slow or unstable uplink, upload the raw layer gzipped instead of running
`carregar-raw.sh`'s plain sync: 88% fewer bytes, same rides, and both Spark
(the Glue job) and Athena read `.json.gz` by extension, so nothing downstream
changes. The data must already be generated in `/tmp/eda-a21`:

```bash
find /tmp/eda-a21/raw/corridas -name '*.json' -exec gzip -n -9 -k -f {} \;
aws s3 rm s3://eda-a21-lake-<suffix>/raw/ --recursive
aws s3 sync /tmp/eda-a21/raw/ s3://eda-a21-lake-<suffix>/raw/ --exclude '*' --include '*.json.gz'
```

`init` and `plan` warn that `dynamodb_table` is deprecated in favour of
`use_lockfile`. It is kept on purpose, as in Lab 03: the course's backend
template locks through the shared `eda-tflock` table, and the two mechanisms do
not see each other, so one member switching alone would let two `apply`s run on
the same state key at once. The switch belongs to Part 2, done by the whole
group: both settings together for a transition, then `use_lockfile` alone with
`init -reconfigure` (same bucket and key, no state migration).

## Results

`verifica.sh`: **70/70** on the automatic criteria; criterion 6 after
destroy; criterion 7 (`DECISOES.md`) is graded by reading.

| # | Criterion | Weight | Result |
|---|---|---|---|
| 0 | remote backend; `trusted` declared as Parquet | eliminatory | OK |
| 1 | `dt` first partition key, 10 columns | 15% | PASSA — `dt` + 10 columns |
| 2 | 518,400 rides in 30 days | 10% | PASSA — 518,400 rides, 30 days |
| 3 | at most 4 files per folder | 10% | PASSA — 30 files, max 1 per folder, 18,143,089 bytes |
| 4 | target ≤ 1 MiB, the 7-day question under it, 11,137 rides | 25% | PASSA — read 355,803 bytes (67.9% of the 524,288 target), 11,137 rides |
| 5 | enforced cutoff blocks the all-columns query | 10% | PASSA — all-columns query CANCELLED at the 10 MiB cutoff |
| 6 | clean `destroy` | 10% | PASSA — 11 destroyed, 0 left in state; re-checked with the real suffix and independently via AWS CLI |
| 7 | `DECISOES.md` | 20% | manual review |

The operator's network failed repeatedly during the run (DNS lookups failing,
one-second AWS calls taking minutes). The first `apply` stopped after 4 of the
11 resources and was recovered with a fresh `plan` (`7 to add`), not a
`destroy`; the second `apply` completed slowly; the raw upload failed once and
stalled once, and went through as gzip (`117,655,606 → 13,945,588` bytes, same
content). Symptoms, recovery and raw output for each are under "Achados da
execução" in [`DECISOES.md`](DECISOES.md).

Criterion 6 needed a second look. On macOS the course's `verifica.sh
--pos-destroy` passes without checking anything: BSD `sed` reads `\s` as a
literal `s`, so `sufixo = "grupo07"` parses to an empty suffix and the script
looks for `eda-a21-lake-`, which never exists. It was re-run with a no-space
`terraform.tfvars` in a temp dir, plus an independent AWS CLI check that prints
the error behind every absence (details in [`DECISOES.md`](DECISOES.md)). This
is the fourth course-verifier bug found across these labs.

Line for the PR, as printed by the verifier:

```
particao=dt  arquivos=30  meta=524288  lido_madrugada_7d=355803  teto=10485760  criterios_auto=70/70  data=2026-10-21T13:56:34Z
```
