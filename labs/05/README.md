# Lab 05 (Exercício 05, Aula 25) — The pipeline that can run again

The Lab-demo 06 Glue job, now in Terraform on the group account, with the
group choosing its arguments. Two real-world problems are planted in the raw
layer: the night (00h–05h) of three days ago arrives only today (an edge
server went down), and the producer re-sends the whole file from five days
ago (the same 17,280 rides arrive twice). The course verifier runs the job a
**second time** and requires the same answer before and after. It is the
second increment of Project Part 2 and has no grade of its own.

The question, fixed for the whole cycle:

```sql
SELECT count(*) FROM corridas
WHERE dt >= '<today - 6>' AND faixa_hora BETWEEN 0 AND 5;   -- 11,137, before and after a re-run
```

## Assignment in short

- the `trusted` table `corridas` declared as Parquet, remote backend (criterion 0, eliminatory);
- the 7-day night count is 11,137, with the late night included and the re-send counted once (20%);
- re-running the job changes nothing: the verifier runs it again and compares (25%);
- one row per ride: `count(*)` = `count(DISTINCT corrida_id)` = 518,400 (15%);
- `terraform plan` clean after apply (10%); clean `destroy` of every `eda-a25-<suffix>` resource (10%);
- `DECISOES.md`: one sentence and one measured number per decision (20%).

## What was decided

Full reasoning and numbers in [`DECISOES.md`](DECISOES.md).

| # | Decision | Choice | Why, in one line |
|---|---|---|---|
| 01 | `modo_escrita` | `sobrescrever` | a re-run replaces the event-day folders it writes instead of adding files: same row count after every run |
| 02 | `chave_dedup` | `corrida_id` | the re-sent file of D-5 collapses to one row per ride (17,280 duplicates removed) |
| 03 | `janela_atraso_dias` | `3` | the smallest window with `fora_da_janela = 0` for this raw; anything later is visible in the report and goes to backfill |
| 04 | backfill | `./rodar-job.sh DIAS=<D-3>` | rewrites only that event day's folder, with every arrival, so it cannot duplicate |

Only the three job arguments in [`terraform/main.tf`](terraform/main.tf)
(`--MODO`, `--CHAVE`, `--JANELA`) and the three values in `terraform.tfvars`
were filled in. The PySpark script is the Lab-demo 06 one, byte for byte.

Before spending money on AWS, every combination was counted locally:
[`verification/model-choices.py`](verification/model-choices.py) re-implements
the job's four rules in plain Python over the same seed-42 raw. Of the 32
combinations, only `sobrescrever` + `corrida_id` + a window of 3 to 7 days
passes criteria 1, 2 and 3 together
([output](docs/evidence/model-choices.txt)). The model also shows why
criterion 3 exists: a window of 1–2 days without a key gets the dashboard
number exactly right (11,137) with a wrong table, because the double-counted
re-send and the dropped late night cancel out.

## Layout

```
labs/05/
├── DECISOES.md                     decisions 01–04, each with a measured number
├── carregar-raw.sh                 course · generates 30 days, plants both problems, uploads the raw
├── rodar-job.sh                    course · runs the Glue job (or a one-day backfill) and prints its report
├── app/
│   ├── gerador-eventos.py          course · deterministic ride generator (seed 42)
│   └── plantar-problemas.py        course · moves the late night and re-sends the D-5 file
├── terraform/
│   ├── main.tf                     the 10 resources (the three job arguments are ours)
│   ├── scripts/pipeline-corridas.py course · the PySpark job (unchanged from Lab-demo 06)
│   ├── backend.hcl.example         template — backend.hcl is gitignored
│   └── terraform.tfvars.example    the three decision values — terraform.tfvars is gitignored
├── verification/
│   ├── verifica.sh                 course · acceptance criteria 0–5
│   ├── measure-run.sh              ours · the table after one job run (counts, files, report)
│   └── model-choices.py            ours · all 32 choices counted locally, no AWS
└── docs/evidence/                  raw output of every step
```

`app/` and the two root scripts keep the course package's names because the
scripts `cd` to their own folder and call `app/` and `terraform -chdir=terraform`.
The course's `verificacao/` became `verification/`, as in Labs 01–04; the
verifier locates the lab root from its own path, so nothing else changed.
Every course file is byte-identical to the package except the three
`← completar` lines in `terraform/main.tf`.

## How to run

From `labs/05/`, with AWS credentials for the group account in the shell.
Every command tees its output (stderr included) into `docs/evidence/`.

```bash
# 0. local model of every choice (no AWS, ~1 min)
python3 -I verification/model-choices.py 2>&1 | tee docs/evidence/model-choices.txt

# 1. backend and variables (same state bucket and lock table as Exercício 04; key aula25/<group>/)
cp terraform/backend.hcl.example terraform/backend.hcl          # replace GRUPO
cp terraform/terraform.tfvars.example terraform/terraform.tfvars  # replace grupoXX
terraform -chdir=terraform init -backend-config=backend.hcl
terraform -chdir=terraform plan -out=lab05.tfplan && terraform -chdir=terraform apply lab05.tfplan

# 2. raw layer with both problems (expected: Total Objects: 32)
./carregar-raw.sh

# 3. run, re-run, backfill — measuring after each
./rodar-job.sh            && ./verification/measure-run.sh
./rodar-job.sh            && ./verification/measure-run.sh
./rodar-job.sh DIAS=<D-3> && ./verification/measure-run.sh

# 4. course verifier (runs the job once more, ~3 min), then destroy
./verification/verifica.sh
terraform -chdir=terraform destroy
./verification/verifica.sh --pos-destroy
rm -rf /tmp/eda-a25
```

On a slow or unstable uplink, upload the raw gzipped instead of running
`carregar-raw.sh` (same generator and planting steps, then
`find /tmp/eda-a25/raw/corridas -name '*.json' -exec gzip -n -9 {} \;` before
the `aws s3 sync`). It is ~88% fewer bytes with the same content, and both
Spark and Athena read `.json.gz` by extension. Exercício 04 needed this.

Dates come from the raw folders, not the clock: "today" is the last `dt=`
folder the generator created, both in `plantar-problemas.py` and in
`verifica.sh`. Unlike Exercício 04, a verifier run after midnight still reads
the same 7-day window.

`init`, `plan` and `apply` warn that `dynamodb_table` is deprecated in favour
of `use_lockfile`. It is kept on purpose, as in Labs 03 and 04: the course's
backend template locks through the shared `eda-tflock` table, and the two
mechanisms do not see each other, so one member switching alone would let two
`apply`s run on the same state key at once.

## Results

`verifica.sh`: **70/70** on the automatic criteria 0–4, then criterion 5 after
destroy. Criterion 6 (`DECISOES.md`) is graded by reading. Run on 2026-11-04
(today = `2026-11-04`, D-3 = `2026-11-01`, D-5 = `2026-10-30`).

| # | Criterion | Weight | Result |
|---|---|---|---|
| 0 | remote backend; `corridas` declared as Parquet | eliminatory | OK |
| 1 | 7-day night = 11,137 | 20% | PASSA — 11,137, the late D-3 night included |
| 2 | re-running changes nothing | 25% | PASSA — 518,400 rows and 11,137 before and after the verifier's re-run |
| 3 | one row per ride | 15% | PASSA — 518,400 rows, 518,400 distinct `corrida_id` |
| 4 | clean `plan` after apply | 10% | PASSA — `plan -detailed-exitcode` = 0 |
| 5 | clean `destroy` | 10% | PASSA — 10 destroyed, 0 left in state; independently re-checked via AWS CLI (5 × service-side not-found) |
| 6 | `DECISOES.md` | 20% | manual review |

The same table, measured after every run (job report + Athena):

| After | Rows | Distinct | Night, 7 days | Folders written | Note |
|---|---|---|---|---|---|
| run 1 | 518,400 | 518,400 | 11,137 | 30 | 535,680 read, 17,280 duplicates removed, 0 outside the window |
| run 2 | 518,400 | 518,400 | 11,137 | 30 | every folder still has 1 file, now from run 2 |
| backfill `DIAS=2026-11-01` | 518,400 | 518,400 | 11,137 | 1 | only `dt=2026-11-01` rewritten; D-5 and today keep run 2's file |
| verifier's re-run | 518,400 | 518,400 | 11,137 | 30 | criterion 2 |

On Glue 4.0 (Spark 3.3), `partitionOverwriteMode=dynamic` and the partition
projection both held. The Lab-demo 06 package had only run them on local
Spark 3.5. About US$ 0.13 of Glue for 4 runs of ~2 min (estimated from the
run clock).

The first `apply` stopped after 6 of the 10 resources on a DNS failure
(`lookup iam.amazonaws.com: no such host`). It was recovered by confirming
the role did not exist (`NoSuchEntity`), then a fresh `plan` guarded to apply
only on `4 to add, 0 to change, 0 to destroy`. Details under "Achados da
execução" in [`DECISOES.md`](DECISOES.md).

Line for the PR, as printed by the verifier:

```
evidência: sufixo=grupo07 hoje=2026-11-04 madrugada_7d=11137->11137 linhas=518400->518400 distintas=518400 {"chave_dedup":"corrida_id","janela_atraso_dias":3,"modo_escrita":"sobrescrever"}
```
