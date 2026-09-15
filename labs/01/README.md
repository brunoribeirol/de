# Lab 01 (Aula 04) — Declared Glue schema with CloudFormation

A minimal raw data lake for ride events, provisioned with **CloudFormation**
and with the schema **declared explicitly** — no Glue Crawler inferring it.
Athena access is capped by a WorkGroup scan limit sized from real measurements.

## Assignment in short

Provision, justify, verify, and tear down:

- an S3 bucket holding raw JSON events partitioned by `dt=YYYY-MM-DD`;
- a Glue database and table with a declared schema (≥ 8 columns, partition key
  `dt`) — a Crawler is an automatic fail;
- ≥ 3 registered partitions, one of them today's;
- an Athena WorkGroup whose bytes-scanned limit blocks a broad query and lets
  a single-partition query through;
- a clean `destroy` with no orphaned resources;
- `DECISOES.md` with one justified decision per open choice (01–05).

## What was built

| Resource | Type |
|---|---|
| `LakeBucket` | `AWS::S3::Bucket` |
| `RawDatabase` | `AWS::Glue::Database` |
| `CorridasTable` | `AWS::Glue::Table` (9 columns, partition key `dt`) |
| `Particao1..3` | `AWS::Glue::Partition` |
| `AnalistasWorkgroup` | `AWS::Athena::WorkGroup` (scan limit `10,716,697` bytes) |

Key decisions (full reasoning and evidence in [`DECISOES.md`](DECISOES.md)):

| # | Decision | Choice |
|---|---|---|
| 01 | `valor` type | `string` — ~1.5% of rows use a comma decimal (`"8,43"`); `double` returns `BAD_DATA` |
| 02 | Temporal columns | `timestamp` — values parse correctly, tested in Athena |
| 03 | `ignore.malformed.json` | `true` — availability first, quality monitored separately |
| 04 | Registered partitions | 3 of 30 — proves "in S3" ≠ "queryable" |
| 05 | Scan limit | total of the 3 partitions minus 1 MiB, measured |

## Layout

```
labs/01/
├── DECISOES.md            # the five decisions, with evidence
├── infra/                 # CloudFormation template, parameters, deploy/destroy
├── scripts/               # synthetic ride-event generator (course-provided)
├── verification/          # verifica.sh — PASS/FAIL per rubric criterion (course-provided)
└── docs/evidence/         # screenshots and command output behind each decision
```

## Run it

Prerequisites: AWS CLI authenticated, Python 3.10+. Run everything from `labs/01/`.
Fill `Turma`, `Owner`, and `TetoBytesPorConsulta` in `infra/parameters.json` first.

```bash
./infra/deploy.sh <login>          # prints the export lines used below
python3 scripts/gerador-eventos.py --dias 30 --taxa 12 --seed 42 --saida ./output/raw/corridas
aws s3 sync ./output/raw/corridas "s3://$BUCKET/raw/corridas/" --region us-east-1
./verification/verifica.sh <login>
./infra/destroy.sh <login>
./verification/verifica.sh <login> --pos-destroy
```

## Results

- Criteria 0–3: `PASSA`. Criterion 5 (post-destroy): `PASSA`, confirmed by a
  manual AWS CLI check.
- Criterion 4: the verifier reports `FALHA`, but the broad query was stopped
  with `CANCELLED` + `Bytes scanned limit was exceeded` and the narrow query
  `SUCCEEDED`. The verifier only accepts `FAILED` as a block — a known
  false-negative in the course script, reproduced in Lab 02.

Evidence: [`docs/evidence/`](docs/evidence/).
