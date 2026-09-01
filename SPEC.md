# SPEC — lakehouse-iac

The reference document for this project: what each tool is responsible for,
where its code lives, how to run it, and how to change it.

---

## 1. The shape of the project

Three things are involved, and they do different jobs:

| Thing | Role | Analogy |
|---|---|---|
| **Databricks** | The platform that stores the data and runs the SQL | The warehouse building |
| **Terraform** | Creates the containers and the permissions on them | The builder who puts up the shelves |
| **dbt** | Fills those containers with tables built from queries | The worker who stocks the shelves |

The important rule, and the reason this project exists:

> **Terraform owns the containers. dbt owns what is inside them.**

Terraform creates the catalog, the schemas, and the grants. It never creates a
table. dbt creates tables and views inside schemas that already exist. It never
creates a schema. If both tools tried to own the same object, they would fight:
one would drop what the other created, and the state would drift.

---

## 2. Where things live

```
lakehouse-iac/
├── infra/                    ← Terraform. The containers.
│   ├── main.tf                  catalog, schemas, grants, warehouse lookup
│   ├── variables.tf             the knobs you can turn
│   ├── outputs.tf               values Terraform hands back (e.g. the dbt http_path)
│   ├── providers.tf             how Terraform authenticates to Databricks
│   └── versions.tf              pinned Terraform and provider versions
│
├── transform/                ← dbt. The tables.
│   ├── dbt_project.yml          project config: which folder becomes which schema
│   ├── profiles.yml             connection settings (no secrets)
│   ├── packages.yml             third-party dbt packages (dbt_utils)
│   ├── macros/                  reusable Jinja; here, the schema-naming override
│   └── models/
│       ├── staging/             one view per source table
│       └── marts/               the business-facing tables
│
├── scripts/                  ← Operational glue.
│   ├── install-tools.sh         downloads terraform + databricks CLI + dbt into the repo
│   ├── env.sh                   puts them on PATH and sets connection env vars
│   ├── uc-catalog.sh            creates/drops the catalog over SQL (see §7)
│   └── bootstrap.sh             installs the AI agent skills and MCP server (optional)
│
├── .bin/                     ← terraform + databricks binaries      (gitignored)
├── .venv/                    ← dbt                                  (gitignored)
└── tools/ai-dev-kit/         ← Databricks MCP server                (gitignored)
```

---

## 3. What the data is, and where it comes from

The source is **`samples.tpch`** — a read-only dataset that Databricks ships
inside every workspace. Nothing is ingested; nothing is downloaded. It is
already sitting in the `samples` catalog when the workspace is created.

TPC-H is a standard benchmark dataset that models a **wholesale supplier**:
customers place orders, each order has line items, each line item references a
part and a supplier, and customers belong to nations which belong to regions.

The five source tables used here:

| Table | Rows | Grain (what one row means) |
|---|---|---|
| `customer` | 750,000 | one customer |
| `orders` | 7,500,000 | one order placed by a customer |
| `lineitem` | 29,999,795 | one product line within an order |
| `nation` | 25 | one country |
| `region` | 5 | one continent-sized region |

It was chosen because it is realistic, relational, and large enough that
incremental models and query performance actually matter — without needing an
ingestion pipeline that would distract from the point of the project.

Columns follow the TPC-H convention of prefixing every column with the table's
initial: `c_custkey`, `o_orderdate`, `l_quantity`. One of dbt's first jobs here
is to rename those into something a human can read.

---

## 4. dbt — what it is and what it does here

### What it is

dbt takes a folder of `SELECT` statements and turns each one into a table or
view in the warehouse. You write the query; dbt writes the `CREATE TABLE AS` or
`CREATE VIEW AS` around it, works out the order to run them in, and runs the
tests you declared.

You never write DDL. You write `SELECT`, and you declare what the result should
be called and how it should be materialised.

The three things dbt adds on top of plain SQL:

1. **`ref()` builds the dependency graph.** When `fct_orders` contains
   `{{ ref('stg_orders') }}`, dbt knows `stg_orders` must be built first, and
   substitutes its real, fully-qualified name at compile time. You never hardcode
   `dev_lakehouse.staging.stg_orders` anywhere.
2. **Tests are declarative.** `unique`, `not_null`, `relationships` are written in
   YAML next to the model, and `dbt build` fails if the data violates them.
3. **Materialisation is a config, not a rewrite.** Changing a model from a view
   to an incremental table is one line; the SQL does not change.

### The two layers in this project

**`models/staging/`** — one view per source table. Materialised as **views**, so
they cost nothing to store and always reflect the source.

Their only job is to make the raw data usable:

- rename columns (`c_custkey` → `customer_key`)
- decode codes once (`o_orderstatus` `'F'` → `'fulfilled'`)
- compute obvious derived columns (`net_amount = gross × (1 − discount)`)

No joins, no business logic, no aggregation. One staging model per source table,
always.

**`models/marts/`** — the business-facing layer. Materialised as **tables**,
because they are queried repeatedly and joins are expensive.

### What a "mart" is

A mart is a table shaped for the question being asked, not for how the data was
stored. Source systems are normalised to avoid duplication; marts are
deliberately denormalised so that answering a question does not require knowing
the source schema.

Concretely: to ask "revenue by region" against the raw data you must join
`orders → customer → nation → region` and know all four key columns. Against
`dim_customers`, `region_name` is simply a column.

The three marts here follow standard dimensional modelling:

| Model | Type | Grain | What it is |
|---|---|---|---|
| `dim_customers` | dimension | one customer | Who the customer is. Name, segment, balance, and their nation and region already joined in. |
| `fct_orders` | fact | one order | What happened. Order date, status, totals, plus aggregates rolled up from its line items. |
| `agg_sales_by_month` | aggregate | month × region × segment | A pre-computed summary. 2,000 rows instead of 7.5M. |

The naming convention is conventional and worth keeping:

- **`dim_`** — a *thing*. Descriptive attributes. Slow-changing. You join to it.
- **`fct_`** — an *event*. Measurements plus foreign keys to dimensions. Grows over time.
- **`agg_`** — a pre-aggregated rollup, built for speed.

`fct_orders` is **incremental**: rather than rebuilding 7.5M rows every run, each
run reprocesses only orders from the last three days and merges them on
`order_key`. The trailing window means a late-arriving line item on a recent
order is still picked up; the merge on a unique key means reprocessing the same
row twice is harmless. That is the standard pattern for a growing fact table.

---

## 5. Terraform — what it is and what it does here

### What it is

Terraform describes the desired state of infrastructure in files. You declare
what should exist; Terraform compares that to what does exist and makes up the
difference. It records what it created in a state file (`infra/terraform.tfstate`)
so it knows the difference between "create this" and "this already exists".

Deleting a resource block and re-applying deletes the real resource. That is the
point: the files are the source of truth, not the console.

### What it manages here

Four things, all in `infra/main.tf`:

1. **`terraform_data.catalog`** — creates the catalog `dev_lakehouse`. It shells
   out to `scripts/uc-catalog.sh` rather than using the normal
   `databricks_catalog` resource; see §7 for why.
2. **`databricks_schema.this`** — creates `staging` and `marts` inside that
   catalog. Driven by the `schemas` variable, so adding a third schema is a
   config change, not new code.
3. **`databricks_grants.catalog`** — grants privileges on the catalog.
4. **`data.databricks_sql_warehouse.this`** — a *lookup*, not a resource. It reads
   the existing warehouse and exports its HTTP path so dbt knows where to connect.
   A `data` block reads; a `resource` block owns.

### How to change it

Almost everything is a variable in `infra/variables.tf`:

| Variable | Default | Effect of changing it |
|---|---|---|
| `environment` | *(required)* | Catalog name prefix. `prod` → catalog `prod_lakehouse`. |
| `project` | `lakehouse` | The other half of the catalog name. |
| `schemas` | `staging`, `marts` | Which schemas exist. Add a key, re-apply, and it is created. |
| `sql_warehouse_name` | `Serverless Starter Warehouse` | Which warehouse to look up. |
| `databricks_profile` | `FREE` | Which Databricks CLI profile to authenticate with. |

**To add a schema** — edit the `schemas` default in `infra/variables.tf`:

```hcl
raw = {
  comment = "Landing zone for raw ingested data."
}
```

Then `terraform -chdir=infra apply -var environment=dev`. The plan will show
`1 to add`.

**To change something structural** — edit `infra/main.tf` directly. Always run
`terraform -chdir=infra plan` first and read it. The plan is a preview: it tells
you exactly what will be created, changed, or destroyed before anything happens.

**Read `destroy` lines in a plan carefully.** Some attribute changes force
Terraform to replace a resource rather than update it, which means dropping and
recreating it. On a schema, that takes the tables with it.

---

## 6. How to run it

### First time on a new machine

```bash
bash scripts/install-tools.sh
source scripts/env.sh
databricks auth login --host https://<your-workspace>.cloud.databricks.com --profile FREE
```

`install-tools.sh` downloads terraform and the databricks CLI into `.bin/` and
installs dbt into `.venv/`. Nothing is installed system-wide. The only
prerequisite on the machine is [uv](https://docs.astral.sh/uv/).

### Every session

```bash
source scripts/env.sh
```

This must be run in every new shell. It puts `.bin` and `.venv/bin` on `PATH`
and sets `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DBT_CATALOG`, and
`DBT_PROFILES_DIR`. Without it, `terraform` and `dbt` are not on `PATH`, and the
Databricks provider cannot find the CLI it needs for OAuth.

### Terraform

```bash
terraform -chdir=infra init                          # once, after cloning
terraform -chdir=infra plan  -var environment=dev    # preview — changes nothing
terraform -chdir=infra apply -var environment=dev    # make it so
terraform -chdir=infra destroy -var environment=dev  # tear it all down
```

`plan` is always safe. Run it before every `apply`.

### dbt

```bash
cd transform

dbt deps      # install packages from packages.yml. Once, after cloning.
dbt build     # run every model, then run every test. The main command.
```

Useful variants:

```bash
dbt run                        # models only, skip tests
dbt test                       # tests only, skip models
dbt build -s stg_customers     # just one model
dbt build -s marts             # everything in the marts folder
dbt build -s +fct_orders       # fct_orders and everything it depends on
dbt build --full-refresh       # rebuild incremental models from scratch
dbt compile -s fct_orders      # write the final SQL to target/ without running it
dbt docs generate && dbt docs serve   # browsable docs with a lineage graph
```

`dbt compile` is the one to reach for when a model misbehaves: it shows the
exact SQL that will be sent to Databricks, with every `ref()` resolved.

### The normal loop

```bash
source scripts/env.sh
terraform -chdir=infra apply -var environment=dev   # only when infra changed
cd transform && dbt build
```

---

## 7. Free Edition constraints

Databricks Free Edition is a real workspace with no cloud storage account
attached. Two consequences are visible in the code, and both were confirmed
against the live workspace rather than assumed.

Measured capability:

| Operation | REST API (what Terraform uses) | SQL |
|---|---|---|
| Create catalog | rejected — Default Storage | works |
| Create schema | works | works |
| Grants | works | works |
| Create SQL warehouse | rejected — only the bundled Starter | — |
| Create job | works | works |

**1. The catalog is created over SQL.** The `databricks_catalog` resource calls a
Unity Catalog endpoint that fails with:

```
Metastore storage root URL does not exist. Default Storage is enabled in your
account. You can use the UI to create a new catalog using Default Storage, or
please provide a storage location for the catalog.
```

There is no storage location to provide. The equivalent `CREATE CATALOG`
statement resolves Default Storage on its own and succeeds, so
`terraform_data.catalog` shells out to `scripts/uc-catalog.sh`. Its destroy
provisioner drops the catalog, so `terraform destroy` still leaves nothing
behind.

**2. The SQL warehouse is a data source, not a resource.** Free Edition ships one
warehouse and will not create another, so Terraform looks it up by name and
exports its HTTP path as an output.

---

## 8. Conventions

**Naming**

- Staging models: `stg_<source_table_plural>` — `stg_customers`, `stg_orders`
- Dimensions: `dim_<entity_plural>` — `dim_customers`
- Facts: `fct_<event_plural>` — `fct_orders`
- Aggregates: `agg_<what>_by_<grain>` — `agg_sales_by_month`
- Columns: `snake_case`, no table prefixes. Keys end in `_key`, timestamps in
  `_at`, booleans start with `is_` or `has_`.

**Model structure** — every model reads top to bottom: import CTEs first (one per
`ref`/`source`), then logic CTEs, then a final `select`. No `SELECT *` except
inside an import CTE.

**Testing** — every model declares at minimum a `unique` and `not_null` test on
its primary key. Every foreign key gets a `relationships` test.

**Secrets** — none in the repository. The OAuth token lives in `~/.databrickscfg`,
managed by the Databricks CLI. `terraform.tfvars` and `.env` are gitignored;
`terraform.tfvars.example` is committed as a template.

---

## 9. Current state

Provisioned and verified against the live workspace:

- Terraform: catalog `dev_lakehouse`, schemas `staging` and `marts`, grants
- dbt: 5 staging views, 3 marts, 32 tests — `dbt build` passes 40/40

| Model | Rows |
|---|---|
| `dim_customers` | 750,000 |
| `fct_orders` | 7,500,000 |
| `agg_sales_by_month` | 2,000 |

## 10. Not built yet

- A `prod` environment, to demonstrate dev → prod promotion
- A Databricks job running `dbt build` on a schedule, provisioned by Terraform
  (the jobs API does work on Free Edition)
- `dbt docs` published as a static site
- A remote Terraform state backend — state is currently local
