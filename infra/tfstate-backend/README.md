# tfstate-backend

Creates the S3 bucket that holds the Terraform state of the lab stacks, and
points at the class-wide DynamoDB lock table.

It is a **separate stack on purpose**. A backend created inside the stack it
serves dies with that stack's `terraform destroy` — and Lab 03 requires the
backend to survive the destroy.

## What it manages

| Resource | Owned here | Why |
| --- | --- | --- |
| `aws_s3_bucket.tfstate` (`eda-tfstate-<grupo>`) | yes | One bucket per group, following the convention already in the account. |
| Versioning | yes | Recovery path for a corrupted or truncated state file. |
| SSE (AES256) + bucket key | yes | State carries resource IDs and sensitive attribute values. |
| Public access block (all four) | yes | A public state bucket is an account-wide disclosure. |
| Lifecycle rule | yes | Expires superseded versions after 90 days, aborts stale multipart uploads. |
| Bucket policy | yes | Denies any request over plaintext HTTP. |
| `eda-tflock` (DynamoDB) | **no** — read via `data` | The table already exists and is shared by the class. Reading it asserts the dependency without claiming ownership. |

## Why the state of this stack is local

Chicken-and-egg: the stack that creates the remote backend cannot store its own
state in a bucket that does not exist yet. The usual answers are:

1. **Local state** (what this does) — the bootstrap state file stays on disk and
   is gitignored. If lost, `terraform import` brings the bucket back under
   management; nothing in AWS is destroyed.
2. Two-phase migration — apply locally, then add a backend block pointing at the
   bucket it just created and migrate into itself. Works, but makes the bucket
   hold the state that guards its own existence: a bad day gets worse.

Option 1 is the common practice and the trade-off is explicit: this single state
file has no remote backup, and it guards resources that are cheap to re-import.

## Usage

```bash
cd infra/tfstate-backend
cp terraform.tfvars.example terraform.tfvars   # fill in grupo and owner

terraform init
terraform plan
terraform apply
```

Then wire a consumer stack to it:

```bash
terraform output -raw backend_hcl   # fill in `key` per stack
```

## Naming: group vs. individual

The account is shared by the whole class, and two different scopes live in it:

- **The backend belongs to the group.** The bucket is `eda-tfstate-<grupo>`,
  matching the IAM login (`eda-grupo07`) and the convention already visible in
  the account (`eda-tfstate-grupo02`, owned by another group). The course
  template spells it `eda-tfstate-CONTA` — account, not personal login.
- **Lab resources belong to the individual.** They keep the personal suffix
  (`eda-a12-brlla-lake`), because each student builds their own stack.

The two meet in the `key`, which carries the individual suffix
(`aula12/brlla/terraform.tfstate`). Sharing one bucket is fine; sharing one key
is not — teammates on the same lab would silently overwrite each other's state,
since the default workspace writes straight to `key`.

Writing into another group's bucket was rejected for the mirror-image reason:
the state would be readable by them and would disappear the day they clean up.

Region: `us-east-1` — must match `region` in every consumer `backend.hcl`.

## Notes

- `prevent_destroy = true` on the bucket. Destroying it would orphan every
  resource of every stack pointing at it: the infrastructure keeps running while
  Terraform believes it manages nothing. To retire it deliberately, remove the
  lifecycle block in a dedicated commit.
- `dynamodb_table` in a consumer `backend.hcl` is deprecated in favour of
  `use_lockfile` (S3-native locking) from Terraform 1.11 on. We keep the
  DynamoDB table because the course requires it.
- Permissions: applying this needs `s3:CreateBucket`, `s3:PutBucketVersioning`,
  `s3:PutEncryptionConfiguration`, `s3:PutBucketPublicAccessBlock`,
  `s3:PutLifecycleConfiguration`, `s3:PutBucketPolicy` and
  `dynamodb:DescribeTable`. On a restricted class IAM user some of these may be
  denied — the error names the missing action.
