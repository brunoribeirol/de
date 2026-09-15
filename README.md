# de — Data Engineering coursework

Coursework repository for the **Engenharia de Dados** course (CESAR School,
Computer Science, 2026.2). Each exercise builds the same underlying skill —
declaring data-lake infrastructure explicitly, instead of letting a tool
infer it — with a different piece of the stack per cycle.

## Labs

| Lab | Topic | IaC | Status |
|---|---|---|---|
| [`labs/01`](labs/01) | Declared Glue schema, no Crawler, Athena scan-limit guardrail | CloudFormation | [PR #1](https://github.com/brunoribeirol/de/pull/1) — merged |
| [`labs/02`](labs/02) | Same data lake, provisioned from scratch, local Terraform state | Terraform | [PR #2](https://github.com/brunoribeirol/de/pull/2) |

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
- No `terraform.tfstate`, no instructor answer keys, and no course-provided
  material marked as instructor-only ever get committed here.
