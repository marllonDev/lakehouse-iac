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

# 5. Build the models — on Databricks, not on this machine
databricks jobs run-now "$(terraform -chdir=infra output -raw tpch_batch_job_id)"
```

Step 2 must be repeated in every new terminal. Steps 1, 3, and 4 are one-time.

**Where dbt runs.** The supported path is a Databricks job: this machine only
edits code, runs Terraform, and calls the Databricks CLI. `dbt` is still
installed into `.venv/` by step 1, and the local commands under `transform/`
below still work, but nothing in the workflow depends on them.

---

## The directory map

```
lakehouse-iac/
├── infra/          Terraform    — creates the containers and the jobs
├── transform/      dbt          — fills the containers
├── jobs/           Python       — entry points that run inside Databricks jobs
├── scripts/        Bash         — installs tooling, sets up the shell
├── .github/        CI           — checks that runs on every push
```

Three of these are the pipeline: `transform/`, `jobs/`, and `infra/` holding it
all up. The rest is tooling.

---

## `infra/` — Terraform

Creates and governs the Unity Catalog objects. Never creates a table.

| File | What it holds |
|---|---|
| `versions.tf` | Pinned Terraform version and the `databricks` provider version. Change here to upgrade. |
| `providers.tf` | Provider block. Empty on purpose: auth comes from the CLI profile, so no secrets in code. |
| `variables.tf` | Every knob. Read this first when you want to change behaviour. |
| `main.tf` | Catalog, schemas, grants, and the SQL warehouse lookup. |
| `batch.tf` | The `tpch-batch` job: dbt Core through the native `dbt_task`. |
| `dbt_v2.tf` | The `dbt-v2-spike` job: dbt v2 through a Python task. |
| `outputs.tf` | Values Terraform hands back — the dbt HTTP path and the job ids and URLs. |
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
| `schemas` | `staging`, `marts` | Which schemas exist. Add a key, re-apply, it appears. |
| `sql_warehouse_name` | `Serverless Starter Warehouse` | Which warehouse to look up and hand to dbt. |
| `databricks_profile` | `FREE` | Which CLI profile the catalog bootstrap authenticates with. |
| `git_repo_url` | this repo | Where the job clones the dbt project from at run time. |
| `git_branch` | `feat/dbt-v2-sail-spike` | Branch **both** jobs clone. One variable on purpose: a Core vs v2 comparison only means something on identical code. |
| `dbt_databricks_version` | `1.12.4` | Adapter the Core job (`tpch-batch`) installs into its serverless environment. |
| `dbt_v2_package` | `dbt` | dbt v2 distribution the spike job installs: `dbt` (dbt Labs licence) or `dbt-oss` (Apache-2.0). |
| `dbt_v2_version` | `2.0.6` | Exact version of that distribution. Never a range: the package fetches binaries when pip builds it. |
| `dbt_v2_environment_version` | `6` | Serverless environment version of the spike job. The Core job stays on 3. |

**Read `plan` output before applying.** Lines starting with `-` or
`-/+` mean destroy. On a schema, that takes its tables with it.

### The jobs

Both jobs have no trigger: nothing runs until you start it with
`databricks jobs run-now`.

| Job | Engine | How it runs dbt |
|---|---|---|
| `dev-lakehouse-tpch-batch` | dbt Core 1.12 + `dbt-databricks` | the native `dbt_task` |
| `dev-lakehouse-dbt-v2-spike` | dbt v2 | a Python task, `jobs/run_dbt_v2.py` |

`dbt_task` only supports dbt Core with the `dbt-databricks` package (the
Databricks documentation says so and its examples pin `<2.0.0`), so dbt v2 needs
a task of its own. The runner is described under `jobs/` below.

The spike job's default commands are `deps` and `parse`, which never touch the
warehouse. Real runs pass their own at trigger time, which replaces the defaults
entirely:

```bash
databricks jobs run-now --no-wait -o json --json '{
  "job_id": <id>,
  "python_params": ["--http-path", "/sql/1.0/warehouses/<warehouse>",
                    "--catalog", "dev_lakehouse",
                    "--command", "deps", "--command", "build"]
}'
```

`--python-params` is not a flag of this CLI version; parameters go in the JSON body.

**Read the trigger's output.** A `run-now` that fails to start prints nothing
useful into a shell variable, and a polling loop around an empty run id waits
forever. Check the id before polling.

---

## `transform/` — dbt

Turns queries into tables. Never creates a schema.

| File / folder | What it holds |
|---|---|
| `dbt_project.yml` | Project config: which model folder writes into which schema. |
| `profiles.yml` | Connection settings. No secrets — host and warehouse come from environment variables. |
| `packages.yml` | Third-party dbt packages. Currently `dbt_utils`. |
| `package-lock.yml` | Resolved package versions. Committed for reproducibility. |
| `macros/` | Reusable Jinja. Holds the `generate_schema_name` override. |
| `models/staging/` | One view per TPC-H source table. Renaming and recasting only. |
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

**`models/marts/`** — materialised as **tables**.

| Model | Grain | Materialisation |
|---|---|---|
| `dim_customers` | one customer | table |
| `fct_orders` | one order | incremental, merge on `order_key` |
| `agg_sales_by_month` | month × region × segment | table |

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
dbt build --full-refresh       # rebuild incremental models from scratch

dbt compile -s fct_orders      # write the final SQL to target/ without running it
dbt docs generate && dbt docs serve   # browsable docs with a lineage graph, local only
```

### Publishing docs

```bash
source scripts/env.sh
scripts/publish-docs.sh
```

Generates the docs site with a live connection — real column types and table
stats, not just what the YAML declares — and pushes it to the `gh-pages`
branch, which GitHub Pages serves directly. Run by hand, deliberately: this is
the same boundary that keeps Databricks credentials out of CI, drawn again for
docs. One-time setup: Settings → Pages → Source: Deploy from a branch →
`gh-pages` / `(root)`.

`dbt compile` is the debugging tool: it shows the exact SQL that will be sent,
with every `ref()` resolved to a real table name.

### Adding a model

1. Write `models/<layer>/<name>.sql` containing a single `select`. Reference
   other models with `{{ ref('other_model') }}`, never a hardcoded table name.
2. Add its description and tests to the `_<layer>__models.yml` in the same folder.
3. `dbt build -s <name>`.

Naming: `stg_` for staging, `dim_` for a thing, `fct_` for an event, `agg_` for
a rollup.

---

## `jobs/` — Python

Entry points that run inside Databricks jobs. Nothing here is run from a laptop:
the code needs the job's identity and the job's compute.

| File | What it does |
|---|---|
| `run_dbt_v2.py` | Runs dbt v2 inside a serverless job, standing in for `dbt_task`. |

What the runner does, in order:

1. Gets a token from the job's own identity through the Databricks SDK. No
   personal access token and no secret file exist anywhere.
2. Writes a throwaway `profiles.yml` that reads every connection value from
   environment variables. The token is never written to disk and is scrubbed
   from the streamed output.
3. Copies `transform/` to local disk and runs from the copy. The Git checkout a
   job runs from lives under `/Workspace/Repos/.internal`, and a native process
   cannot create directories there (`os error 22`), while dbt v2 needs `logs/`,
   `target/` and `dbt_packages/` next to the project.
4. Runs each `--command` in order, stops at the first failure, and prints one
   `RESULT` line with the duration of each.

It does not install dbt: the job environment pins the distribution and version.
It raises `SystemExit` only on failure, because a Databricks task treats any
`SystemExit`, including `sys.exit(0)`, as a failed run.

Arguments: `--http-path`, `--catalog` (required); `--schema` (default
`staging`); `--threads` (default 8, the same as the Core job, so timings are
comparable); `--command` (repeatable).

---

## `scripts/` — operational glue

| File | What it does | When you run it |
|---|---|---|
| `install-tools.sh` | Downloads terraform and the databricks CLI into `.bin/`, installs dbt into `.venv/`. Nothing system-wide. | Once, after cloning. |
| `env.sh` | Puts `.bin` and `.venv/bin` on PATH; sets `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DBT_CATALOG`, `DBT_PROFILES_DIR`. | **Every new shell.** `source` it, do not execute it. |
| `uc-catalog.sh` | Creates or drops the catalog over the SQL API. Called by Terraform, not by you. | Never directly. |

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

## AI assistant tooling — not part of the pipeline

Nothing in this repository exists for an AI assistant. Databricks agent skills
are installed once per machine as a plugin, outside the project:

```bash
databricks aitools install --agents claude-code --scope global
```

---

## Directories you will see but should not commit

All gitignored:

| Path | What it is | Safe to delete? |
|---|---|---|
| `.bin/` | terraform and databricks binaries | Yes — `install-tools.sh` recreates it |
| `.venv/` | dbt and its dependencies | Yes — `uv sync` recreates it |
| `transform/target/` | Compiled SQL and run artifacts | Yes |
| `transform/dbt_packages/` | Installed dbt packages | Yes — `dbt deps` recreates it |
| `infra/.terraform/` | Downloaded providers | Yes — `terraform init` recreates it |
| `infra/terraform.tfstate` | Record of what exists | **No.** Deleting it orphans real resources. |

---

## The job, and why it needs GitHub

The Databricks job runs on compute in the cloud. That compute has no access to
your laptop, so the dbt project has to reach it somehow. This project uses
`git_source`: at run time, Databricks clones the repository at the configured
branch and runs from that checkout.

```
run-now
  └─ clone repo at the configured branch
  └─ dbt deps, dbt build   (Core: dbt_task · v2: jobs/run_dbt_v2.py)
```

The consequence worth understanding: **the branch a job clones is what runs.**
Both jobs follow the `git_branch` variable, so they always run the same code. There
is no separate deployment step: a commit on that branch is live on the next run.

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
databricks jobs run-now "$(terraform -chdir=infra output -raw tpch_batch_job_id)"
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
| Job task fails `dbt: command not found` | Serverless environments start empty | Declare the adapter in the environment's `dependencies` — `dbt_databricks_version` handles it for the Core job and `dbt_v2_package` for the spike |
| dbt fails `UC_HIVE_METASTORE_DISABLED_EXCEPTION` | A dbt task generates its own profile and ignores `profiles.yml`; with no catalog it falls back to the legacy metastore | Set `catalog` and `schema` on the `dbt_task` block |
| v2 job: `NameError: name '__file__' is not defined` | A Databricks Python task runs the script through `exec(compile(...))` | Use `main.__code__.co_filename`, as the runner does |
| v2 job: `Failed to create directory ... (os error 22)` | The Git checkout under `/Workspace/Repos/.internal` refuses directory creation from a native process | Run from a scratch copy on local disk, as the runner does |
| v2 job reported failed with `SystemExit: 0` although dbt succeeded | A Databricks task treats every `SystemExit` as a failure | Return normally on success |
| `databricks jobs run-now`: `unknown flag: --python-params` | That flag does not exist in this CLI version | Pass `python_params` in the `--json` body |
| dbt model exists but is empty after a code change | Incremental model kept its old rows | `dbt build -s <model> --full-refresh` |
