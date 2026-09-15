# de — Data Engineering coursework

Coursework repository for the **Engenharia de Dados** course (CESAR School,
Computer Science, 2026.2). Each exercise builds the same underlying skill —
declaring data-lake infrastructure explicitly, instead of letting a tool
infer it — with a different piece of the stack per cycle.

## Labs

| Lab | Topic | IaC | Status |
|---|---|---|---|
| [`labs/01`](labs/01) | Declared Glue schema, no Crawler, Athena scan-limit guardrail | CloudFormation | [PR #1](https://github.com/brunoribeirol/de/pull/1) — merged |
| [`labs/02`](labs/02) | Same data lake, provisioned from scratch, local Terraform state | Terraform | [PR #2](https://github.com/brunoribeirol/de/pull/2) — merged |

Each lab's own `README.md` has the exact deploy/verify/destroy commands.
Each lab's `DECISOES.md` documents the required engineering decisions —
schema types, partitioning, and Athena cost guardrails — with evidence, not
assumption.

## Stack

AWS (S3, Glue Data Catalog, Athena), Terraform and CloudFormation, Python
for synthetic data generation.

## Conventions

- One exercise per `labs/NN/` directory, self-contained (its own
  `terraform/` or `infra/`, `docs/`, `verification/`).
- `DECISOES.md` per lab: one justified paragraph per required decision,
  backed by a measurement or a query result, not a guess.
- `docs/evidence/` per lab: the raw command output or screenshot behind
  each decision and each verification step.
- Only authored work is published. Course-provided material (slides,
  enunciados, rubricas, answer keys) stays local; each lab's `README.md`
  summarizes the assignment instead. Scripts the course ships and the
  solution depends on (data generator, `verifica.sh`) are kept so each lab
  stays reproducible.
- No `terraform.tfstate` or filled-in `terraform.tfvars`/`backend.hcl` —
  only their `*.example` templates.
- Language: code, READMEs, and commits are in English. `DECISOES.md` and the
  course-provided scripts are in Portuguese, because the rubric grades them in
  that language under that file name.
