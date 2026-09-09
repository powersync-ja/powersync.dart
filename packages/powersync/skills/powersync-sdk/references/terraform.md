---
name: powersync-terraform
description: PowerSync Terraform provider — provisioning and managing PowerSync Cloud projects and instances as infrastructure-as-code
metadata:
  tags: terraform, iac, infrastructure-as-code, powersync, cloud, powersync_project, powersync_instance, powersync_organization, PS_PAT_TOKEN, hcl, provisioning
---

# PowerSync Terraform Provider

> **Load this when** the operator is using Terraform to provision or manage PowerSync Cloud infrastructure, or asks about managing PowerSync via IaC. This covers Cloud only — for self-hosted deployments, use `references/powersync-service.md` and `references/powersync-cli.md`.

Provider source: `powersync-ja/powersync` on the [Terraform Registry](https://registry.terraform.io/providers/powersync-ja/powersync/latest/docs). Minimum Terraform version: 1.5.

## When to Use Terraform vs the CLI

- If the operator is managing PowerSync alongside other cloud resources (databases, networking, compute) in Terraform, use the Terraform provider — it provisions the PowerSync project and instance in the same `terraform apply`.
- If the operator needs IaC-reviewable config (plan diffs in PRs), multi-environment parity, or version-controlled infrastructure, prefer Terraform.
- If the operator is working interactively or only needs to deploy sync config, prefer the PowerSync CLI (`references/powersync-cli.md`).
- Terraform manages the project and instance lifecycle; `sync_config_content` on the instance resource replaces `powersync deploy sync-config`. You do not run the CLI alongside Terraform for the same instance.

## Authentication

The provider authenticates via a personal access token. Set it as an environment variable before any `terraform` command:

```sh
export PS_PAT_TOKEN="jpt_..."
```

The provider reads `PS_PAT_TOKEN` automatically — do not inline the token in HCL. Direct operators who need a token to: **Dashboard → Account → Access Tokens**.

## Provider Declaration

```hcl
terraform {
  required_providers {
    powersync = {
      source  = "powersync-ja/powersync"
      version = "~> 0.1"
    }
  }
}

provider "powersync" {
  # Reads PS_PAT_TOKEN from env automatically.
  # admin_token = var.admin_token  # only if env var is not viable
}
```

Run `terraform init` to download the provider binary.

## Organization

Organizations are not Terraform-managed resources — they exist when you sign up. Use a data source to reference one:

```hcl
data "powersync_organization" "main" {
  id = "<org-id>"   # hex segment from the dashboard URL: /orgs/<id>/
}
```

## Project Resource

```hcl
resource "powersync_project" "main" {
  org_id = data.powersync_organization.main.id
  name   = "my-project"
  region = "us"   # supported: eu, us, jp, au, br
}
```

If `force_destroy = true` is not set and the project contains instances created outside Terraform, `terraform destroy` will fail. Set `force_destroy = true` on the project resource to override this safety check.

## Instance Resource

`powersync_instance` wires together replication, client auth, and sync config:

```hcl
variable "replication_password" {
  type      = string
  sensitive = true
}

resource "powersync_instance" "main" {
  org_id     = data.powersync_organization.main.id
  project_id = powersync_project.main.id
  name       = "production"

  replication_connection {
    type     = "postgresql"
    name     = "main"
    hostname = "db.<project-ref>.supabase.co"
    port     = 5432
    username = "powersync_role"
    password = var.replication_password
    database = "postgres"
    sslmode  = "verify-full"
  }

  client_auth {
    supabase               = true
    allow_temporary_tokens = true
  }

  sync_config_content = <<-YAML
    config:
      edition: 3
    streams:
      todos:
        auto_subscribe: true
        query: SELECT * FROM todos WHERE user_id = auth.user_id()
  YAML
}
```

Pass `replication_password` (and any other sensitive values) via environment variable — never in plaintext config or state:

```sh
export TF_VAR_replication_password="..."
terraform plan
terraform apply
```

## sync_config_content

`sync_config_content` is a Sync Streams YAML string. It must start with `config: edition: 3`. For non-trivial configs, load from a file:

```hcl
sync_config_content = file("${path.module}/sync-config.yaml")
```

For the full Sync Streams reference, load `references/sync-config.md`.

## Managing Changes

- To update any field, edit the HCL and re-run `terraform plan` then `terraform apply`.
- Every change to `powersync_instance` triggers a full redeploy. The instance ID and URL remain the same.
- `terraform show` displays the full resource state including the instance URL after apply.

## Destroying Resources

```sh
terraform destroy
```

- Removes the instance and the project.
- If the project contains instances not tracked by this Terraform state, destroy fails unless `force_destroy = true` is set on `powersync_project`.

## Critical Pitfalls

- Never inline credentials in HCL or state. Use `TF_VAR_*` environment variables for sensitive Terraform variables.
- `sync_config_content` must include the `config: edition: 3` wrapper — the same requirement as `sync-config.yaml` for the CLI. Missing this wrapper causes validation/deploy failures.
- Terraform manages the full instance lifecycle. Do not mix CLI deploys (`powersync deploy`) against the same instance managed by Terraform — the two tools will overwrite each other's changes.
- For Supabase source databases, the Supabase publication and `powersync_role` still need to be configured separately (Terraform does not manage source-DB-side replication setup). See `references/supabase-auth.md`.
