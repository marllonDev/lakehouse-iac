# lakehouse-iac

A small but complete analytics platform on **Databricks Free Edition**, where the
platform itself is code: **Terraform** provisions and governs the Unity Catalog
objects, and **dbt** owns every relation inside them.

The point of the project is the seam between those two tools. Terraform and dbt
will happily both try to own a schema, and the result is drift and destroyed
tables. Here the line is drawn explicitly:

| Layer | Owner | What it manages |
|---|---|---|
| Catalog, schemas, grants | Terraform | The containers and who may read them |
| Tables, views, tests | dbt | The relations inside those containers |

`generate_schema_name` is overridden so dbt writes into the exact schema names
Terraform created, instead of dbt's default `<target>_<custom>` mangling.

## What it builds

Source is `samples.tpch`, the read-only TPC-H dataset present in every
Databricks workspace — 750k customers, 7.5M orders, 30M order lines. No
ingestion pipeline is needed, so the project stays focused on modelling and
governance.

```
samples.tpch  ──▶  dev_lakehouse.staging  ──▶  dev_lakehouse.marts
  (source)          5 views, renamed          dim_customers
                    and recast                fct_orders  (incremental, merge)
                                              agg_sales_by_month
```

`fct_orders` is incremental: each run reprocesses a three-day trailing window and
merges on `order_key`, so late-arriving order lines are picked up without
rebuilding 7.5M rows.

## Running it

Everything is installed inside the repository. The only prerequisite on the
machine is [uv](https://docs.astral.sh/uv/).

```bash
bash scripts/install-tools.sh      # terraform + databricks CLI into .bin, dbt into .venv
source scripts/env.sh              # put them on PATH, set connection env vars
databricks auth login --host https://<your-workspace>.cloud.databricks.com --profile FREE

terraform -chdir=infra init
terraform -chdir=infra apply -var environment=dev

cd transform && dbt deps && dbt build
```

`scripts/bootstrap.sh` additionally installs the Databricks agent skills and MCP
server used while developing this repo with an AI assistant. It is optional.

## Free Edition constraints, and what they forced

Free Edition is not a cut-down API — it is a real workspace with no cloud
account attached, and that changes what infrastructure code can do. Measured
against the live workspace:

| Operation | REST API (what Terraform uses) | SQL |
|---|---|---|
| Create catalog | ✗ rejected — Default Storage | ✓ |
| Create schema | ✓ | ✓ |
| Grants | ✓ | ✓ |
| Create SQL warehouse | ✗ — only the bundled Starter | — |
| Create job | ✓ | ✓ |

Two consequences are visible in the Terraform code:

1. **The catalog is created over SQL.** `databricks_catalog` calls a Unity
   Catalog endpoint that refuses to run without a storage root, and Free Edition
   has no storage location to give it. The equivalent `CREATE CATALOG` statement
   resolves Default Storage on its own, so `terraform_data.catalog` shells out to
   `scripts/uc-catalog.sh`. Its destroy provisioner drops the catalog, so
   `terraform destroy` still leaves nothing behind.
2. **The SQL warehouse is a data source, not a resource.** Free Edition ships one
   warehouse and will not create another, so Terraform looks it up by name and
   feeds its HTTP path to dbt through an output.

Both are deliberate: the code stays honest about the boundary rather than
pretending an unavailable API works.

## Layout

```
infra/          Terraform: catalog, schemas, grants, warehouse lookup
transform/      dbt project: sources, staging views, marts, tests
scripts/        tool installation, environment, catalog bootstrap
.github/        CI: format, validate, dbt parse
```
