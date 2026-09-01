# USAGE — how to run this project, folder by folder

This document explains what every directory is for, what each file in it does,
and which commands touch it. [SPEC.md](SPEC.md) explains *why* the project is
built this way; this file explains *how to operate it*.

---

## Quick start

```bash
# 1. Install the toolchain into the repository (needs uv, nothing else)
bash scripts/install-tools.sh

# 2. Put it on PATH and load connection settings — every new shell
source scripts/env.sh

# 3. Authenticate once per machine
databricks auth login --host https://<your-workspace>.cloud.databricks.com --profile FREE

# 4. Create the Unity Catalog objects
terraform -chdir=infra init
terraform -chdir=infra apply -var environment=dev

# 5. Build the models
cd transform && dbt deps && dbt build
```

Step 2 must be repeated in every new terminal. Steps 1, 3, and 4 are one-time.

---

## The directory map

```
lakehouse-iac/
├── infra/          Terraform    — creates the containers
├── transform/      dbt          — fills the containers
├── ingest/         Python       — brings data in from outside
├── scripts/        Bash         — installs tooling, sets up the shell
├── .github/        CI           — checks that runs on every push
├── .claude/        Agent config — skills, not part of the pipeline
└── tools/          Vendored     — Databricks MCP server, not part of the pipeline
```

Three of these are the pipeline: `ingest/` → `transform/` → and `infra/` holding
it all up. The rest is tooling.

---

## `infra/` — Terraform

Creates and governs the Unity Catalog objects. Never creates a table.

| File | What it holds |
|---|---|
| `versions.tf` | Pinned Terraform version and the `databricks` provider version. Change here to upgrade. |
| `providers.tf` | Provider block. Empty on purpose: auth comes from the CLI profile, so no secrets in code. |
| `variables.tf` | Every knob. Read this first when you want to change behaviour. |
| `main.tf` | Catalog, schemas, grants, and the SQL warehouse lookup. |
| `streaming.tf` | The landing volume and the Wikimedia ingestion job. |
| `outputs.tf` | Values Terraform hands back — the dbt HTTP path, the job URL, the landing path. |
| `terraform.tfvars.example` | Template. Copy to `terraform.tfvars` (gitignored) to stop passing `-var` on every command. |
| `.terraform.lock.hcl` | Provider checksum lock. Committed on purpose so every machine resolves identically. |
| `terraform.tfstate` | What Terraform believes exists. Local, gitignored, **do not delete** — losing it orphans the real resources. |

### Commands

```bash
terraform -chdir=infra init                          # once after cloning, and after changing versions.tf
terraform -chdir=infra plan  -var environment=dev    # preview. Changes nothing. Run this first, always.
terraform -chdir=infra apply -var environment=dev    # make reality match the files
terraform -chdir=infra output                        # show the outputs
terraform -chdir=infra destroy -var environment=dev  # remove everything it created
```

### How to change things

Almost everything is a variable. To change behaviour, edit the `default` in
`infra/variables.tf` (or pass `-var name=value`), then re-apply.

| Variable | Default | What changing it does |
|---|---|---|
| `environment` | *required* | Catalog name prefix. `prod` → catalog `prod_lakehouse`. |
| `project` | `lakehouse` | The other half of the catalog name. |
| `schemas` | `raw`, `staging`, `marts` | Which schemas exist. Add a key, re-apply, it appears. |
| `sql_warehouse_name` | `Serverless Starter Warehouse` | Which warehouse to look up and hand to dbt. |
| `databricks_profile` | `FREE` | Which CLI profile the catalog bootstrap authenticates with. |
| `git_repo_url` | this repo | Where the job clones the dbt project from at run time. |
| `git_branch` | `main` | Which branch the job runs. |
| `streaming_mode` | `triggered` | `triggered` = scheduled runs. `continuous` = never exits, true real time. |
| `ingest_schedule_cron` | every 5 min | Quartz cron, used only in `triggered` mode. |
| `ingest_window_seconds` | `180` | How long one triggered run consumes the firehose. Keep below the schedule interval. |
| `ingest_batch_seconds` | `60` | How often ingestion flushes a landing file. |
| `wikis` | `enwiki,ptwiki` | Which wikis to keep. Empty string keeps all of them. |

**Read `plan` output before applying.** Lines starting with `-` or
`-/+` mean destroy. On a schema, that takes its tables with it.

### Switching to true real time

```bash
terraform -chdir=infra apply -var environment=dev -var streaming_mode=continuous
```

The job stops being scheduled and instead holds the SSE connection open
permanently, restarting the task if it drops. Latency goes from minutes to
seconds. Compute then runs 24/7, which on Free Edition consumes the account's
limited serverless allowance quickly. Switch back with
`-var streaming_mode=triggered`.

---

## `transform/` — dbt

Turns queries into tables. Never creates a schema.

| File / folder | What it holds |
|---|---|
| `dbt_project.yml` | Project config: which model folder writes into which schema, and the `wikipedia_landing_path` var. |
| `profiles.yml` | Connection settings. No secrets — host and warehouse come from environment variables. |
| `packages.yml` | Third-party dbt packages. Currently `dbt_utils`. |
| `package-lock.yml` | Resolved package versions. Committed for reproducibility. |
| `macros/` | Reusable Jinja. Holds the `generate_schema_name` override. |
| `models/staging/` | One view per TPC-H source table. Renaming and recasting only. |
| `models/streaming/` | The streaming table reading the landing volume. |
| `models/marts/` | Business-facing tables. |
| `target/` | Compiled SQL, run artifacts, `manifest.json`. Gitignored, safe to delete. |
| `dbt_packages/` | Installed packages. Gitignored, recreated by `dbt deps`. |

### The models

**`models/staging/`** — materialised as **views**, so they cost nothing to store.
Rename columns, decode codes, compute obvious derived fields. No joins, no
business logic.

| Model | Source |
|---|---|
| `stg_customers` | `samples.tpch.customer` |
| `stg_orders` | `samples.tpch.orders` |
| `stg_order_lines` | `samples.tpch.lineitem` |
| `stg_nations` | `samples.tpch.nation` |
| `stg_regions` | `samples.tpch.region` |

**`models/streaming/`** — materialised as a **streaming table**.

| Model | Reads |
|---|---|
| `st_wikipedia_edits` | JSON files in the landing volume, incrementally via Auto Loader |

Auto Loader tracks which files it has already consumed, so refreshing is cheap
and never double-counts. This is why the ingestion task writes immutable files
with unique names and never rewrites them.

**`models/marts/`** — materialised as **tables**.

| Model | Grain | Materialisation |
|---|---|---|
| `dim_customers` | one customer | table |
| `fct_orders` | one order | incremental, merge on `order_key` |
| `agg_sales_by_month` | month × region × segment | table |
| `fct_wikipedia_edits` | one edit event | incremental, merge on `edit_key` |
| `agg_wikipedia_activity` | minute × wiki | table |

`fct_wikipedia_edits` carries `ingestion_lag_seconds` — the delay between the
edit happening on Wikipedia and this pipeline landing it. Pipeline latency is a
column you can query, not a claim in a README.

### Commands

```bash
cd transform

dbt deps                       # install packages. Once after cloning.
dbt build                      # run every model, then every test. The main command.

dbt run                        # models only
dbt test                       # tests only
dbt build -s dim_customers     # one model
dbt build -s marts             # everything in the marts folder
dbt build -s +fct_orders       # fct_orders and everything upstream of it
dbt build -s st_wikipedia_edits+   # the streaming table and everything downstream
dbt build --full-refresh       # rebuild incremental models from scratch

dbt compile -s fct_orders      # write the final SQL to target/ without running it
dbt docs generate && dbt docs serve   # browsable docs with a lineage graph
```

`dbt compile` is the debugging tool: it shows the exact SQL that will be sent,
with every `ref()` resolved to a real table name.

### Adding a model

1. Write `models/<layer>/<name>.sql` containing a single `select`. Reference
   other models with `{{ ref('other_model') }}`, never a hardcoded table name.
2. Add its description and tests to the `_<layer>__models.yml` in the same folder.
3. `dbt build -s <name>`.

Naming: `stg_` for staging, `dim_` for a thing, `fct_` for an event, `agg_` for
a rollup, `st_` for a streaming table.

---

## `ingest/` — Python

The one part dbt cannot do. dbt has no HTTP client and no long-running process,
so bringing data in from outside the warehouse needs real code.

| File | What it does |
|---|---|
| `wikipedia_stream.py` | Holds the Wikimedia EventStreams SSE connection open and flushes batches of events as JSON Lines files into the landing volume. |

It is written in Databricks notebook source format (`# Databricks notebook
source` header, `# COMMAND ----------` cell separators) so the job can run it
straight from Git without a build step, while it stays a readable `.py` file in
the repository.

Parameters, passed by the job from Terraform variables:

| Widget | Meaning |
|---|---|
| `volume_path` | Where to write. Must match dbt's `wikipedia_landing_path` var. |
| `batch_seconds` | How often to flush a file. |
| `max_seconds` | How long to run. `0` means never exit — continuous mode. |
| `wikis` | Comma-separated wiki codes to keep. Empty keeps all. |

You do not run this locally. It runs as a task on Databricks, because that is
where the volume is.

---

## `scripts/` — operational glue

| File | What it does | When you run it |
|---|---|---|
| `install-tools.sh` | Downloads terraform and the databricks CLI into `.bin/`, installs dbt into `.venv/`. Nothing system-wide. | Once, after cloning. |
| `env.sh` | Puts `.bin` and `.venv/bin` on PATH; sets `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DBT_CATALOG`, `DBT_PROFILES_DIR`. | **Every new shell.** `source` it, do not execute it. |
| `uc-catalog.sh` | Creates or drops the catalog over the SQL API. Called by Terraform, not by you. | Never directly. |
| `bootstrap.sh` | Installs the Databricks agent skills and MCP server used for AI-assisted development. | Optional. |

Tool versions are pinned at the top of `install-tools.sh`. Change the variable,
re-run the script, and the binary is replaced.

**Why `source` and not `./`** — `env.sh` modifies the current shell's PATH.
Executing it in a subshell would set variables that vanish when it exits.

Forgetting to source it produces `command not found: terraform`, and — more
confusingly — a Terraform error saying `databricks CLI not found`, because the
provider shells out to the CLI for OAuth.

---

## `.github/workflows/` — CI

| File | What it checks |
|---|---|
| `ci.yml` | `terraform fmt -check`, `terraform validate`, and `dbt parse` on every push and pull request. |

CI has no Databricks credentials, so it only checks that the code is
syntactically valid and internally consistent. Anything that touches the real
workspace runs from a developer machine. That is a deliberate boundary: a
public repository should never hold credentials that can write to a warehouse.

---

## `.claude/` and `tools/` — not part of the pipeline

`.claude/skills/` holds Databricks agent skills, project-scoped. `tools/ai-dev-kit/`
holds the Databricks MCP server. Both are gitignored and reinstalled by
`scripts/bootstrap.sh`. They help while developing this repository with an AI
assistant and have no role at run time. Delete them and the pipeline still works.

---

## Directories you will see but should not commit

All gitignored:

| Path | What it is | Safe to delete? |
|---|---|---|
| `.bin/` | terraform and databricks binaries | Yes — `install-tools.sh` recreates it |
| `.venv/` | dbt and its dependencies | Yes — `uv sync` recreates it |
| `transform/target/` | Compiled SQL and run artifacts | Yes |
| `transform/dbt_packages/` | Installed dbt packages | Yes — `dbt deps` recreates it |
| `tools/ai-dev-kit/` | Vendored MCP server | Yes — `bootstrap.sh` recreates it |
| `infra/.terraform/` | Downloaded providers | Yes — `terraform init` recreates it |
| `infra/terraform.tfstate` | Record of what exists | **No.** Deleting it orphans real resources. |

---

## The job, and why it needs GitHub

The Databricks job runs on compute in the cloud. That compute has no access to
your laptop, so the dbt project has to reach it somehow. This project uses
`git_source`: at run time, Databricks clones the repository at the configured
branch and runs from that checkout.

```
job triggers
  └─ task "ingest"     clone repo → run ingest/wikipedia_stream.py
  │                    → writes JSON files into the landing volume
  └─ task "transform"  same checkout → dbt deps, dbt build
                       → dbt reads the volume, materialises the models
```

The consequence worth understanding: **the `main` branch on GitHub is what runs
in production.** Merge, and the next execution uses the new code. There is no
separate deployment step — which also means an untested commit on `main` is
live on the next trigger.

### One-time setup for the job

Databricks needs permission to clone the repository:

```bash
databricks git-credentials create gitHub \
  --personal-access-token <your-github-pat> \
  --git-username <your-github-username>
```

Generate the token at **GitHub → Settings → Developer settings → Personal access
tokens**, with `repo` scope for a private repository. Store it in a password
manager; it is not needed again and must never be committed.

Then:

```bash
terraform -chdir=infra apply -var environment=dev
databricks jobs run-now --job-id "$(terraform -chdir=infra output -raw wikipedia_job_id)"
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `command not found: terraform` | `env.sh` not sourced | `source scripts/env.sh` |
| Terraform: `databricks CLI not found` | `.bin` not on PATH; the provider shells out to the CLI for OAuth | `source scripts/env.sh` |
| dbt: `Env var required but not provided` | Connection variables not set | `source scripts/env.sh` |
| Terraform: `Metastore storage root URL does not exist` | The catalog is being created through the REST API instead of SQL | Expected on Free Edition — see [SPEC.md](SPEC.md) §7 |
| Job fails `REPOSITORY_CHECKOUT_FAILED` / `UNAUTHENTICATED` | No Git credential linked in Databricks | Settings → Linked accounts → link GitHub |
| Job fails `REPOSITORY_CHECKOUT_FAILED` / `PERMISSION_DENIED` | Account linked, but the Databricks GitHub App is not installed on the repository | Install at github.com/apps/databricks/installations/new; if scoped to selected repositories, add this one |
| Job task fails `dbt: command not found` | Serverless environments start empty | Declare the adapter in the environment's `dependencies` — `dbt_databricks_version` handles this |
| dbt fails `UC_HIVE_METASTORE_DISABLED_EXCEPTION` | A dbt task generates its own profile and ignores `profiles.yml`; with no catalog it falls back to the legacy metastore | Set `catalog` and `schema` on the `dbt_task` block |
| Runs silently missing, `MAX_CONCURRENT_RUNS_EXCEEDED` | The schedule fires faster than a run completes; with concurrency capped at one the trigger is dropped, not queued | Widen `ingest_schedule_cron` or shorten `ingest_window_seconds` |
| Streaming table returns zero rows | No files have landed yet | Run the ingest task first, then `dbt build -s st_wikipedia_edits+` |
| dbt model exists but is empty after a code change | Incremental model kept its old rows | `dbt build -s <model> --full-refresh` |
