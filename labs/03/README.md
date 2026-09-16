# Lab 03 (Aula 12) — Refactor into a module, with a clean plan

The only lab of the semester that builds nothing new. The flat stack from Lab 02
becomes **module + remote backend + workspace**, under one hard rule: the final
`terraform plan` must say **"No changes"**. Same infrastructure, different code,
zero resources recreated.

Wrapping resources in a module changes every address in the state. Terraform, if
allowed, destroys and recreates everything to "fix" the difference. The craft is
changing the code without AWS noticing — `terraform state mv` is the tool, and
the clean plan is the proof.

## Assignment in short

- the six resources move into `modules/lake/` **without being renamed**;
- the state moves with them (`state mv` or `moved {}`) **before** any apply;
- state migrates from local disk to the shared S3 backend;
- a named workspace exists, and the migrated stack stays on `default`;
- the five contract outputs survive (`bucket_name`, `database_name`,
  `table_name`, `workgroup_name`, `teto_bytes`);
- `plan` clean, `destroy` clean, `DECISOES.md` with decisions 01–05.

## What was refactored

| Before (Lab 02) | After |
|---|---|
| six `resource` blocks in the root | one `module "lake"` call; the six live in `modules/lake/main.tf`, unrenamed |
| outputs read from resources | the same five outputs re-exported from `module.lake.*` |
| `terraform.tfstate` on local disk | `s3://eda-tfstate-grupo07/aula12/brlla/terraform.tfstate`, locked by `eda-tflock` |
| no workspaces | `dev` created; the stack stays on `default` |

Key decisions (full reasoning and evidence in [`DECISOES.md`](DECISOES.md)):

| # | Decision | Choice |
|---|---|---|
| 01 | Module boundary | the lake goes in; provider, validation, backend and the output contract stay in the root |
| 02 | Moving the state | six `terraform state mv` — explicit, auditable, and disposable once done |
| 03 | Workspace vs. folder | workspace, because the environments differ only in name; the migrated stack stays on `default` |
| 04 | What a clean plan proves | code matches state — **not** that AWS matches the code (drift outside the state is invisible) |
| 05 | Order of operations | applying before `state mv` would destroy the lake bucket and its data, then collide on recreate |

Also documented: **the shared backend did not exist** and was provisioned as a
separate Terraform stack in [`infra/tfstate-backend/`](../../infra/tfstate-backend/);
the `dynamodb_table` deprecation in Terraform 1.16; and a third verifier bug in
the course scripts (stderr read as stdout).

## Layout

```
labs/03/
├── DECISOES.md                    decisions 01–05 + findings
├── docs/evidence/                 one folder per decision, plus environment/
├── terraform/
│   ├── main.tf                    the module call
│   ├── backend.tf                 backend "s3" (partial config)
│   ├── backend.hcl.example        template — backend.hcl is gitignored
│   ├── providers.tf variables.tf versions.tf outputs.tf
│   └── modules/lake/              the six resources, unrenamed
└── verification/verifica.sh       course verifier
```

## Run it

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars      # sufixo = your login
cp backend.hcl.example backend.hcl                # bucket = eda-tfstate-<group>
                                                  # key    = aula12/<login>/terraform.tfstate

terraform init -backend-config=backend.hcl
terraform plan -var="sufixo=<login>"              # expect: No changes
```

The state bucket must exist first — see
[`infra/tfstate-backend/`](../../infra/tfstate-backend/). The `key` carries the
individual suffix because the bucket belongs to the group: on the `default`
workspace, a shared key means teammates silently overwrite each other's state.

Do not apply while the `dev` workspace is selected: its state is empty, and an
apply there would try to build a second copy of every resource.

## Results

`verifica.sh`: **80/80** on the automatic criteria — everything the script can
measure. Criterion 6 is graded by reading `DECISOES.md`.

| # | Criterion | Weight | Result |
|---|---|---|---|
| 0 | module + remote backend + workspace | eliminatory | OK |
| 1 | clean `plan` | 30% | PASSA — No changes |
| 2 | state in the remote backend | 15% | PASSA |
| 3 | a named workspace in use | 10% | PASSA |
| 4 | the five contract outputs | 10% | PASSA |
| 5 | clean `destroy` | 15% | PASSA — 6 destroyed, 0 orphaned |
| 6 | `DECISOES.md` | 20% | manual review |

The destroy was also checked independently with the AWS CLI, as in Labs 01 and
02: the Glue database and the Athena WorkGroup are confirmed absent, not just
the buckets the verifier looks at
([`docs/evidence/destroy/manual-cleanup-check.txt`](docs/evidence/destroy/manual-cleanup-check.txt)).
The state bucket survived the destroy, which is the point of keeping the backend
in its own stack.

The refactor kept the state's lineage intact across all six moves
(`736e9225…`, serial 7 → 13), and the plan was clean twice: once with local
state, once after the migration to S3 — which separates the effect of the module
from the effect of the backend.
