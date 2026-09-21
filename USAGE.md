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
| `bench.tf` | The `dbt-core` and `dbt-v2` jobs: the same Python runner, one job per engine. |
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
| `git_branch` | `feat/dbt-v2-sail-spike` | Branch **every** job clones. One variable on purpose: a Core vs v2 comparison only means something on identical code. |
| `dbt_databricks_version` | `1.12.4` | Adapter the Core jobs (`tpch-batch`, `dbt-core`) install into their serverless environment. |
| `dbt_v2_package` | `dbt` | dbt v2 distribution the `dbt-v2` job installs: `dbt` (dbt Labs licence) or `dbt-oss` (Apache-2.0). |
| `dbt_v2_version` | `2.0.6` | Exact version of that distribution. Never a range: the package fetches binaries when pip builds it. |
| `dbt_environment_version` | `6` | Serverless environment version of every dbt job. One variable on purpose: an engine comparison is only fair on the same base environment. |

**Read `plan` output before applying.** Lines starting with `-` or
`-/+` mean destroy. On a schema, that takes its tables with it.

### The jobs

No job has a trigger: nothing runs until you start it with
`databricks jobs run-now`.

| Job | Engine | How it runs dbt |
|---|---|---|
| `dev-lakehouse-tpch-batch` | dbt Core 1.12 + `dbt-databricks` | the native `dbt_task`, `dbt deps` then `dbt build` |
| `dev-lakehouse-dbt-core` | dbt Core 1.12 + `dbt-databricks` | a Python task, `jobs/run_dbt.py --engine core` |
| `dev-lakehouse-dbt-v2` | dbt v2 (`dbt==2.0.6`) | a Python task, `jobs/run_dbt.py --engine v2` |

`dbt_task` only supports dbt Core with the `dbt-databricks` package (the
Databricks documentation says so and its examples pin `<2.0.0`), so dbt v2 needs
a task of its own. `dbt-core` and `dbt-v2` exist so that both engines run
through the same runner, on the same environment version: any difference between
them is the engine and nothing else. The runner is described under `jobs/` below.
`tpch-batch` stays as the reference for the native job type.

`tpch-batch` builds the whole project with its own commands. The two runner jobs
have `deps` and `parse` as defaults, which never touch the warehouse; real runs
pass their own at trigger time, which replaces the defaults entirely:

```bash
databricks jobs run-now --no-wait -o json --json '{
  "job_id": <id>,
  "python_params": ["--engine", "v2",
                    "--http-path", "/sql/1.0/warehouses/<warehouse>",
                    "--catalog", "dev_lakehouse",
                    "--command", "deps", "--command", "build", "--report"]
}'
```

`--python-params` is not a flag of this CLI version; parameters go in the JSON body.
The job ids come from `terraform -chdir=infra output dbt_job_ids`.

To build a subset with dbt Core through `tpch-batch`, override its commands:
`{"job_id": <id>, "dbt_commands": ["dbt deps", "dbt build --select marts"]}`.

**Read the trigger's output.** A `run-now` that fails to start prints nothing
useful into a shell variable, and a polling loop around an empty run id waits
forever. Check the id before polling.

---

## `transform/` — dbt

Turns queries into tables. Never creates a schema.

| File / folder | What it holds |
|---|---|
| `dbt_project.yml` | Project config: which model folder writes into which schema. Seeds and intermediate models go to `staging`. |
| `profiles.yml` | Connection settings. No secrets — host and warehouse come from environment variables. |
| `packages.yml` | Third-party dbt packages. Currently `dbt_utils`. |
| `package-lock.yml` | Resolved package versions. Committed for reproducibility. |
| `macros/` | Reusable Jinja: the `generate_schema_name` override and `safe_divide`, which returns null instead of failing on a zero divisor. |
| `models/staging/` | One view per source table, in a folder per dataset (`tpcds/`, `wanderbricks/`, `clickbench/`; TPC-H sits at the top). Renaming and recasting only. |
| `models/intermediate/` | Joins and reshaping shared by several marts, by dataset. Views in the `staging` schema. |
| `models/marts/` | Business-facing tables, by dataset. |
| `seeds/` | Three small CSV reference tables: shipping-mode SLAs, payment-method fees, order-priority weights. |
| `snapshots/` | The history of hosts and properties, kept in `marts`. |
| `tests/` | Eleven singular tests: SQL that must return no rows. They reconcile layers against each other. |
| `target/` | Compiled SQL, run artifacts, `manifest.json`. Gitignored, safe to delete. |
| `dbt_packages/` | Installed packages. Gitignored, recreated by `dbt deps`. |

### The models

146 models in all. The original TPC-H ones are written by hand; the rest are
generated (see `scripts/generate/` below), and the generated files carry no
hand edits.

**`models/staging/`** — 49 views, materialised as views so they cost nothing to
store. Rename columns, decode codes, compute obvious derived fields. No joins, no
business logic. One per source table:

| Folder | Models | Source |
|---|---|---|
| top level | 8: `stg_customers`, `stg_orders`, `stg_order_lines`, `stg_nations`, `stg_regions`, `stg_suppliers`, `stg_parts`, `stg_part_suppliers` | `samples.tpch` |
| `tpcds/` | 24, `stg_tpcds__<table>` | `samples.tpcds_sf1`, table prefixes stripped |
| `wanderbricks/` | 16, `stg_wanderbricks__<table>` | `samples.wanderbricks` |
| `clickbench/` | 1, `stg_clickbench__hits` | `samples.clickbench`, the 22 of 105 columns the marts use |

**`models/intermediate/`** — 25 views: 10 for TPC-DS, 8 for Wanderbricks, 5 for
TPC-H, 2 for ClickBench. Examples: `int_wb__sessions` cuts a click stream into
sessions at every thirty-minute gap; `int_tpch__order_lines_enriched` attaches
each line to its order and computes days to ship.

**`models/marts/`** — 72 tables, named by the convention below.

| Folder | Models | Materialisation |
|---|---|---|
| top level | `dim_customers`, `fct_orders`, `agg_sales_by_month` | table; `fct_orders` incremental, merge on `order_key` |
| `tpcds/` | 6 dimensions, 4 facts, 16 aggregates | tables |
| `wanderbricks/` | 4 dimensions, 5 facts, 11 aggregates | tables; `fct_wb_bookings` and `fct_wb_payments` incremental merges |
| `tpch/` | 3 dimensions, 2 facts, 10 aggregates | tables; `fct_tpch_order_lines` is about 30M rows |
| `clickbench/` | 1 fact, 7 aggregates | tables, over 100M events |

Naming: `dim_` a thing, `fct_` an event, `agg_` a rollup; intermediate models are
`int_<dataset>__<what>`.

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

Naming: `stg_` for staging, `int_` for intermediate, `dim_` for a thing, `fct_`
for an event, `agg_` for a rollup. To change a generated model, edit its
generator under `scripts/generate/` and rerun it; a hand edit is overwritten.

---

## `jobs/` — Python

Entry points that run inside Databricks jobs. Nothing here is run from a laptop:
the code needs the job's identity and the job's compute.

| File | What it does |
|---|---|
| `run_dbt.py` | Runs dbt, either engine, inside a serverless job, standing in for `dbt_task`. |

What the runner does, in order:

1. Gets a token from the job's own identity through the Databricks SDK. No
   personal access token and no secret file exist anywhere.
2. Writes a throwaway `profiles.yml` that reads every connection value from
   environment variables. The token is never written to disk and is scrubbed
   from the streamed output. dbt v2 needs `auth_type: token` spelled out;
   dbt Core takes the token from the `token` key alone, so the profile differs by
   that one line per engine.
3. Copies `transform/` to local disk and runs from the copy. The Git checkout a
   job runs from lives under `/Workspace/Repos/.internal`, and a native process
   cannot create directories there (`os error 22`), while dbt v2 needs `logs/`,
   `target/` and `dbt_packages/` next to the project.
4. Runs each `--command` in order, stops at the first failure, and prints one
   `RESULT` line with the duration of each.
5. With `--report`, prints three more lines: `NODES` (what the last build did:
   counts by status, a digest of node ids and statuses, the slowest nodes),
   `WAREHOUSE` (statements, and how long the warehouse was busy, from its query
   history) and `PARITY` (a row count and two whole-row checksums for every
   relation in `staging` and `marts`).

It does not install dbt: the job environment pins the distribution and version.
It raises `SystemExit` only on failure, because a Databricks task treats any
`SystemExit`, including `sys.exit(0)`, as a failed run.

Arguments: `--engine` (`core` or `v2`), `--http-path`, `--catalog` (required);
`--schema` (default `staging`); `--threads` (default 8, the same for both
engines); `--command` (repeatable); `--report`.

The `WAREHOUSE` figures cover every statement on the warehouse during the run, so
run one job at a time and put nothing else on the warehouse. The numbers of the
engine comparison, and how it was run, are in [BENCHMARK.md](BENCHMARK.md).

---

## `scripts/` — operational glue

| File | What it does | When you run it |
|---|---|---|
| `install-tools.sh` | Downloads terraform and the databricks CLI into `.bin/`, installs dbt into `.venv/`. Nothing system-wide. | Once, after cloning. |
| `env.sh` | Puts `.bin` and `.venv/bin` on PATH; sets `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DBT_CATALOG`, `DBT_PROFILES_DIR`. | **Every new shell.** `source` it, do not execute it. |
| `uc-catalog.sh` | Creates or drops the catalog over the SQL API. Called by Terraform, not by you. | Never directly. |
| `generate/generate_staging.py` | Writes the staging models and their sources from `samples_schema.json`, a snapshot of the sample tables' columns, so it needs no warehouse connection. | After changing the snapshot or the key lists. |
| `generate/generate_marts.py` | Writes the intermediate and mart models and their tests from the `models_<dataset>.py` modules next to it. | After editing any model in those modules. |

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
  └─ dbt deps, dbt build   (Core: dbt_task or jobs/run_dbt.py · v2: jobs/run_dbt.py)
```

The consequence worth understanding: **the branch a job clones is what runs.**
Every job follows the `git_branch` variable, so they always run the same code. There
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
| Job task fails `dbt: command not found` | Serverless environments start empty | Declare the adapter in the environment's `dependencies` — `dbt_databricks_version` handles it for the Core jobs and `dbt_v2_package` for the v2 job |
| dbt fails `UC_HIVE_METASTORE_DISABLED_EXCEPTION` | A dbt task generates its own profile and ignores `profiles.yml`; with no catalog it falls back to the legacy metastore | Set `catalog` and `schema` on the `dbt_task` block |
| Warehouse figures in a report are far above the build time | Something else ran on the warehouse during the window | Run one job at a time, and nothing else, while benchmarking |
| v2 job: `NameError: name '__file__' is not defined` | A Databricks Python task runs the script through `exec(compile(...))` | Use `main.__code__.co_filename`, as the runner does |
| v2 job: `Failed to create directory ... (os error 22)` | The Git checkout under `/Workspace/Repos/.internal` refuses directory creation from a native process | Run from a scratch copy on local disk, as the runner does |
| v2 job reported failed with `SystemExit: 0` although dbt succeeded | A Databricks task treats every `SystemExit` as a failure | Return normally on success |
| `databricks jobs run-now`: `unknown flag: --python-params` | That flag does not exist in this CLI version | Pass `python_params` in the `--json` body |
| dbt model exists but is empty after a code change | Incremental model kept its old rows | `dbt build -s <model> --full-refresh` |
