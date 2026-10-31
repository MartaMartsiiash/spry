# ADR 0007 — CloudFormation → Terraform for auth, reports, and AI

## Context

Labs 4–6 added three CloudFormation stacks (`auth`, `reports`, `ai`). They work, but the infrastructure lived only inside AWS stacks: no shared review of “what will change”, weak multi-provider story (Google OAuth / GitHub already sit outside AWS), and a second environment would mean copying YAML. Lab 7 asks who creates the cloud and where it is written down.

## Decision

1. **Terraform (HCL) in `infra/`** owns Cognito (auth), the weekly report stack, and the agenda parser. One root module, one HCP Terraform workspace (`successfulsuccess-dev`), remote execution.
2. **State in HCP Terraform**, not on a laptop and not in Git. Applies run in HCP after review; the Makefile may run `terraform plan` / `terraform output`, not `terraform apply`.
3. **Existing resources were adopted** (`DeletionPolicy: Retain` → delete stacks → `import` → plan until **No changes**). Cognito users and report objects were not re-created.
4. **Secrets** (`google_client_secret`, `database_url`, AWS keys for the run role) live as **sensitive variables in the HCP workspace**, not in `terraform.tfvars`.
5. **OIDC dynamic credentials for HCP → AWS** are blocked on this Free project by an SCP (`iam:CreateOpenIDConnectProvider`). Workaround for the course: a dedicated IAM user whose access keys are workspace env vars. Prefer OIDC if/when the SCP allows it.

Network/API/database/frontend CloudFormation stacks stay as they are; Terraform can read their outputs later via `aws_cloudformation_stack` data sources if needed.

## Alternatives considered

| Alternative | Why it lost |
|-------------|-------------|
| Keep CloudFormation only | Fine for one AWS account, but no single tool for Google/GitHub; change sets are optional; second env is copy-paste |
| AWS CDK | Still CloudFormation under the hood; another language/runtime for a course that already standardised on Terraform in class |
| OpenTofu | Compatible CLI; HCP Terraform + classroom screenshots target HashiCorp’s hosted product |
| Recreate resources instead of import | Would wipe Cognito users and report history |

## Consequences

- **Who can change infra:** anyone with rights on the HCP org/workspace; changes go plan → review → apply (VCS preferred). Laptop `apply` is for emergencies / bootstrap only.
- **Secrets & state:** state JSON is in HCP (versioned, locked). Sensitive values are in workspace variables; `sensitive = true` hides them in plan output, not inside state.
- **If HCP Terraform is down:** existing AWS resources keep running; app deploys via GitHub Actions still work for code. You cannot change infra until HCP (or a local backend with credentials) is back; do not “fix in the console” without importing the change afterward.
- **Cost:** Terraform CLI is free; HCP free tier is enough for this project. No extra idle VPC endpoints from this migration.
