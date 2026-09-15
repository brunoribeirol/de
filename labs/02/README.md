# Lab 02 (Aula 08) — Declared data lake in Terraform, from scratch

The same raw data lake idea as Lab 01, now provisioned **100% in Terraform**
with **local state** (by design for this cycle): bucket, declared Glue schema,
registered partitions, and an Athena WorkGroup with a measured scan limit.

## Assignment in short

- HCL only, `aws_glue_catalog_table` with a declared schema (≥ 8 columns,
  partition key `dt`) — a Crawler or a YAML delivery is an automatic fail;
- the five contract outputs (`bucket_name`, `database_name`, `table_name`,
  `workgroup_name`, `teto_bytes`) — the verifier reads these names;
- ≥ 3 registered partitions, one of them today's, `location` matching the S3 key;
- a scan limit that blocks the broad query and lets the narrow one through;
- a clean `terraform destroy` with no orphaned resources;
- `DECISOES.md` with one justified decision per open choice (01–05).

## What was built

| Resource | Purpose |
|---|---|
| `aws_s3_bucket.lake` + public access block | raw events under `raw/corridas/dt=YYYY-MM-DD/` |
| `aws_s3_bucket.results` + public access block | Athena query results |
| `aws_glue_catalog_database.db` | catalog database |
| `aws_glue_catalog_table.corridas` | 9 declared columns, partition key `dt` |
| `aws_glue_partition.p` | `for_each` over `dias_particao` (4 registered) |
| `aws_athena_workgroup.wg` | enforced scan limit `12,522,547` bytes |

Key decisions (full reasoning and evidence in [`DECISOES.md`](DECISOES.md)):

| # | Decision | Choice |
|---|---|---|
| 01 | `valor` type | `decimal(10,2)` — 0 comma decimals in 128,000 rows, so exact money precision wins |
| 02 | Temporal columns | `string` — values are time-only; `CAST` to `timestamp` returned `NULL` in 5/5 rows |
| 03 | `ignore.malformed.json` | `true` — preventive, availability first |
| 04 | Registered partitions | 4 — with 3, the broad scan (~10.18 MB) sits below the Athena limit floor (10,485,760) |
| 05 | Scan limit | broad scan (13,571,123) minus 1 MiB, measured |

Also documented: a Terraform 1.16 HCL incompatibility in the course scaffold
([`docs/evidence/environment/`](docs/evidence/environment/)).

## Layout

```
labs/02/
├── DECISOES.md            # the five decisions, with evidence
├── terraform/             # versions, providers, variables, main, outputs, tfvars example
├── scripts/               # synthetic ride generator (course-provided)
├── verification/          # verifica.sh — PASS/FAIL per rubric criterion (course-provided)
└── docs/evidence/         # command output behind each decision and verification step
```

## Run it

Prerequisites: AWS CLI authenticated, Terraform ≥ 1.5 (validated on 1.16.0), Python 3.

```bash
export AWS_REGION=us-east-1
cd labs/02/terraform
cp terraform.tfvars.example terraform.tfvars      # fill sufixo, teto_bytes, dias_particao
python3 ../scripts/gerar-corridas.py --dias 8 --saida ../output
terraform init && terraform apply
aws s3 cp ../output/ "s3://$(terraform output -raw bucket_name)/raw/corridas/" --recursive
cd ../verification && ./verifica.sh
cd ../terraform && terraform destroy
cd ../verification && ./verifica.sh --pos-destroy
```

`terraform.tfvars` and `terraform.tfstate` are gitignored — never commit them.

## Results

- Criteria 0–3: `PASSA`; criterion 6 found all decisions. Criterion 5
  (post-destroy): `PASSA`, plus a manual AWS CLI check (bucket, database, and
  WorkGroup all absent).
- Criterion 4: the verifier reports `FALHA`, but the broad query ended
  `CANCELLED` with `Bytes scanned limit was exceeded` and the narrow query
  `SUCCEEDED` (3,393,451 bytes). Same verifier false-negative as Lab 01
  (it only accepts `FAILED`).

Evidence: [`docs/evidence/`](docs/evidence/).
