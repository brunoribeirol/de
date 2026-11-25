# Lab 06 (Exercício 06, Aula 29) — The lake in layers, and who reads each one

The three layers of Lab-demo 07 (raw → trusted → refined) in Terraform, with
AWS Lake Formation deciding who reads what. The scenario has two consumers.
The Recife mobility office (*Prefeitura*) gets a night-by-district dashboard,
on one condition from the legal team: it may never see any id (ride, driver
or passenger). The in-house operations analyst (*analista*) investigates
complained rides in the trusted layer, but not people, so she may not see
`passageiro_id`. The course verifier asks **as each profile** and checks what
is answered and what is refused. It is the third and last increment of
Project Part 2 and has no grade of its own.

## Assignment in short

- remote backend; three Glue databases, one per layer; the refined
  `madrugada_bairro` in Parquet (criterion 0, eliminatory);
- as the Prefeitura, the 7-day night in the refined is 11,137 (20%);
- as the Prefeitura, the trusted and the raw are refused by Athena, and so is
  direct S3 (25%, "criterion 2 is the exercise");
- as the analyst, `count(bairro)` on the trusted is 518,400 and
  `SELECT passageiro_id` is refused (15%);
- the refined's contract in the catalog: a description of at least 40
  characters, an owner, a comment on every column (10%);
- clean `destroy`, Lake Formation registrations included (10%);
- `DECISOES.md`: one sentence and one measured piece of evidence per decision (20%).

## What was decided

Full reasoning and evidence in [`DECISOES.md`](DECISOES.md).

| # | Decision | Choice | Why, in one line |
|---|---|---|---|
| 01 | `escopo_prefeitura` | `tabela` | a new refined table stays invisible to the Prefeitura until someone grants it; measured: a probe table created after the apply gave the Prefeitura `TABLE_NOT_FOUND` and the analyst (database wildcard) 11,137 |
| 02 | `colunas_ocultas_analista` | `motorista_id`, `passageiro_id` | she "does not investigate people", and a driver is a person too; `corrida_id` stays because a complaint arrives with it |
| 03 | `contrato_refined` | description, owner, update cadence, 3 column comments | what the table answers, what it does not have (no id), its grain, and where to go instead (the trusted) |

The nine `← completar` lines in `terraform/main.tf` are wired to the three
variables. The group's values are in `terraform/terraform.tfvars.example`,
because `terraform.tfvars` itself is gitignored.
DECISÃO 01 sets either `name` or `wildcard` from `var.escopo_prefeitura` and
leaves the other `null`.

## One course line changed: the consumption policy

The package as shipped let no profile run any query. Every Athena call as
the Prefeitura or the analyst failed with `Unable to verify/create output
bucket` (`INSUFFICIENT_PERMISSIONS`), so the first verifier run scored
**35/70**. Criterion 2 passed only because everything was refused. In the
`consumo` policy, `s3:GetBucketLocation` shared a statement with
`s3:ListBucket` under an `s3:prefix` condition. Only `ListBucket` requests
carry that key. For `GetBucketLocation` the condition is always false, and
Athena checks the results bucket with that call before every query.

The fix gives `GetBucketLocation` its own statement, with no condition; it
reveals only the bucket's region. `ListBucket` keeps the prefix condition, so
listing `refined/` as the Prefeitura is still refused (measured before and
after). It was applied with
`-target=aws_iam_policy.consumo`, guarded on `0 to add, 1 to change, 0 to
destroy`, so nothing else in the shared account moved. Every other course
file is byte-identical to the package, except `terraform.tfvars.example`,
which carries the group's values.

## The account is shared: Lake Formation settings are saved and given back

`aws_lakeformation_data_lake_settings` is one object for the whole AWS
account. Before the apply it held three Lake Formation admins: two other
groups and the teaching assistant. New databases and tables were open to
`IAMAllowedPrincipals`. The course template **replaces** the admin list
with whoever runs Terraform, and Terraform's delete **empties** the list and
the default permissions, for every group. So the run saves the settings
first, under `.private/`, gitignored because they hold the account id. The
teardown then:

1. takes that one resource out of the state (`terraform state rm`) before the
   `destroy`, so the `destroy` never touches the account settings;
2. destroys the other 31 resources;
3. gives the account back the admins it had before, plus anyone another
   group added in the meantime, minus the ones this apply put in, and the
   default permissions as they were.

## Layout

```
labs/06/
├── DECISOES.md                     decisions 01–03, each with what was measured as the profile
├── carregar-raw.sh                 course · generates 30 days, plants both Cycle 6 problems, uploads the raw
├── rodar-jobs.sh                   course · raw → trusted, then trusted → refined, prints each report
├── como.sh                         course · runs one SQL in Athena AS a profile (assumes its role)
├── app/                            course · ride generator (seed 42) and problem planter — identical to Lab 05
├── terraform/
│   ├── main.tf                     the 32 resources; the 9 decision lines and the policy fix are ours
│   ├── variables.tf                course · the three decisions, with validations
│   ├── scripts/                    course · the two PySpark jobs (pipeline-corridas.py is Lab 05's, byte for byte)
│   ├── backend.hcl.example         template — backend.hcl is gitignored
│   └── terraform.tfvars.example    the group's three decision values — terraform.tfvars is gitignored
├── verification/
│   ├── verifica.sh                 course · criteria 0–5
│   ├── run-lab.sh                  ours · settings backup → guarded apply → load → jobs → profiles → probe → verifier
│   └── teardown.sh                 ours · state rm of the account settings → destroy → checks → settings back
└── docs/evidence/                  raw output of every step (account id replaced by <account>)
```

As in Labs 01–05, the course's `verificacao/` became `verification/`. The
verifier finds the lab root from its own path, so nothing else changed.

## How to run

From `labs/06/`, with credentials for the class account (profile `de` by
default; set `AWS_PROFILE` to use another one). Every step tees stdout and
stderr into `docs/evidence/`.

```bash
cp terraform/backend.hcl.example terraform/backend.hcl          # Exercício 05's bucket and lock table; key aula29/<group>/
cp terraform/terraform.tfvars.example terraform/terraform.tfvars  # set the suffix; the three decisions are filled in
bash verification/run-lab.sh     # ~10 min: apply (only on "32 to add"), load, both jobs, profile questions, verifier
# read docs/evidence/, then:
bash verification/teardown.sh    # destroy, criterion 5, independent check, Lake Formation settings back
```

`run-lab.sh` pauses after printing the caller identity, so a wrong profile
stops before anything is created. Its probe for DECISÃO 01 creates
`sonda_tabela_nova` in the refined, on the same files, asks as both
profiles, and deletes it.

## Results

`verifica.sh`: **70/70** on the automatic criteria 0–4 (after the policy
fix), on 2026-11-25 (today = `2026-11-25`, since = `2026-11-19`).

| # | Criterion | Weight | Result |
|---|---|---|---|
| 0 | remote backend; 3 databases; refined in Parquet | eliminatory | OK |
| 1 | the Prefeitura reads the refined: 11,137 | 20% | PASSA — 11,137 (998 bytes scanned) |
| 2 | and only the refined | 25% | PASSA — trusted and raw refused (`Required Describe on …`), `s3 ls refined/` refused |
| 3 | the analyst reads the trusted without the hidden ids | 15% | PASSA — 518,400; `passageiro_id` refused (`COLUMN_NOT_FOUND`) |
| 4 | the refined's contract in the catalog | 10% | PASSA — 241-character description, owner, a comment on every column |
| 5 | clean `destroy` | 10% | PASSA — 30 destroyed, empty state; re-checked per service (404 / `EntityNotFound` / `NoSuchEntity`), no Lake Formation registration or permission left |
| 6 | `DECISOES.md` | 20% | manual review |

What each profile got, beyond the verifier ([`profiles.txt`](docs/evidence/profiles.txt),
[`probe-new-refined-table.txt`](docs/evidence/probe-new-refined-table.txt)):

| As | Question | Answer |
|---|---|---|
| Prefeitura | refined, whole table | 660 rows = 22 districts × 30 days |
| Prefeitura | a refined table created after the grants | `TABLE_NOT_FOUND` |
| analyst | the same new table | 11,137 (database wildcard) |
| analyst | `SELECT *` on the trusted | 9 of the 11 columns + `dt` (no driver, no passenger) |
| analyst | `SELECT motorista_id` | refused (`COLUMN_NOT_FOUND`) |
| analyst | `count(DISTINCT corrida_id)` | 518,400 |

Both jobs held the Cycle 6 numbers: the trusted read 535,680 raw rows,
removed 17,280 duplicates, kept 0 outside the window, and wrote 518,400
rows. The refined wrote 660 rows, with 47,730 night rides over the 30 days
([jobs](docs/evidence/jobs-run-1.txt)). About US$ 0.05 of Glue, estimated
from the run clock.

Line for the PR, as printed by the verifier:

```
evidência: sufixo=grupo07 hoje=2026-11-25 prefeitura_refined=11137 prefeitura_trusted=RECUSADO prefeitura_raw=RECUSADO prefeitura_s3=RECUSADO analista_trusted=518400 analista_passageiro=RECUSADO {"colunas_ocultas_analista":["motorista_id","passageiro_id"],"escopo_prefeitura":"tabela"}
```

Teardown: 32 created, 1 taken out of the state (the account settings), and
30 destroyed, not 31. During the destroy's refresh the provider stopped
finding `analista_refined`, the analyst's database-wildcard grant on the
refined. That grant was live at 12:36, when she read 11,137 there. A search
for any Lake Formation permission naming `eda-a29-grupo07` or
`eda_a29_grupo07` came back empty after the destroy, because deleting the
database took its grants with it. The account's Lake Formation settings
were given back exactly: the same 3 admins and `IAMAllowedPrincipals` as
the default for new databases and tables
([`lf-settings-restored.txt`](docs/evidence/lf-settings-restored.txt)).

`init` and `plan` warn that `dynamodb_table` is deprecated in favour of
`use_lockfile`. It is kept on purpose, as in Labs 03–05, because the class
locks through the shared `eda-tflock` table.
