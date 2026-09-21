# dbt Core vs dbt v2 on Databricks

A controlled comparison of dbt Core (`dbt-databricks` 1.12.4) and dbt v2 (`dbt`
2.0.6) building the same project, on the same warehouse, inside Databricks.
Nothing ran on a developer machine.

Raw numbers: [`benchmarks/2026-09-20-core-vs-v2.json`](benchmarks/2026-09-20-core-vs-v2.json).

## What was compared

The project has 146 models, 3 seeds, 2 snapshots, 398 data tests and 4 unit
tests, which is 553 nodes per `dbt build`. It reads four Databricks sample
datasets (TPC-H, TPC-DS, Wanderbricks, ClickBench), the largest being 100 million
rows, and it builds 151 relations.

Everything except the engine was held identical:

| Held constant | How |
|---|---|
| Code | One commit, one Git branch, cloned by both jobs |
| Runner | The same script, [`jobs/run_dbt.py`](jobs/run_dbt.py), in both jobs |
| Base environment | Serverless environment version 6 in both jobs |
| Warehouse | The same Starter SQL warehouse |
| Parallelism | `--threads 8` in both |
| Authentication | The job's own identity, through the Databricks SDK |
| Load | One job at a time, nothing else on the warehouse |

The jobs differ only in the pip package the environment installs. Terraform
defines both in [`infra/bench.tf`](infra/bench.tf).

Each job ran `deps`, `parse`, `parse` again, `compile` and `build`, then wrote
three reports: what the last build did node by node, what the warehouse did
during the run (from its query history), and a checksum of every relation.

Protocol: one warm-up run, discarded, then six runs alternating the engines
(v2, Core, Core, v2, v2, Core) so that drift in the warehouse hits both alike.
Figures below are medians of the three runs per engine.

## Results

| Step | dbt Core | dbt v2 | Difference |
|---|---:|---:|---:|
| `deps` | 3.9 s | 0.4 s | 9.8x faster |
| `parse` (cold) | 10.9 s | 1.0 s | 10.9x faster |
| `parse` (repeat) | 6.5 s | 1.0 s | 6.5x faster |
| `compile` | 16.1 s | 2.5 s | 6.4x faster |
| `build` | 232.0 s | 213.7 s | 8% faster |
| Whole job | 341.6 s | 284.4 s | 17% faster |
| Environment install | 4 s | 4 s | none |

Range across the three runs of each engine:

| Step | Core | v2 |
|---|---|---|
| `parse` (cold) | 10.1 to 11.1 s | 1.0 to 1.1 s |
| `compile` | 15.3 to 16.6 s | 2.4 to 2.7 s |
| `build` | 226.7 to 235.2 s | 210.5 to 218.5 s |

The ranges do not overlap for any step, so the ordering is not noise. The size of
the effect on `build` is small, and three runs per engine on a shared free-tier
warehouse is not enough to put a tight interval on it.

### Where the build time goes

`build` is dominated by the warehouse, not by dbt. The warehouse query history
shows the time during which at least one statement was running:

| | dbt Core | dbt v2 |
|---|---:|---:|
| `build` wall time | 232.0 s | 213.7 s |
| Warehouse busy (whole run, all commands) | 217.6 s | 212.2 s |
| `build` wall time minus warehouse busy time | about 14 s | about 1.5 s |
| Statements sent to the warehouse | 705 | 863 |

Both engines keep the warehouse busy for about 212 to 218 seconds. What v2
saves is the dbt-side overhead: the gap between the build's wall time and the
time the warehouse was working shrinks from about 14 seconds to about 1.5. The
busy figure also covers the few statements of `compile`, so the gap is
approximate. That is the whole build gain, and it is why the
gain is small on a warehouse-bound project. A project that spends less time in
SQL and more in dbt itself, such as many small models, would see more of it.

v2 sends 158 more statements than Core for the same build. This was not
investigated; the extra work costs it nothing measurable in wall time here.

### Correctness

Both engines produced the same result:

- **Same nodes.** All six runs touched the same 553 nodes with the same status
  (151 built, 397 tests passed, 5 warnings). A digest of the sorted node ids and
  statuses is identical across all six runs.
- **Same warnings.** The 5 warnings are the same in both: four Wanderbricks
  sources that repeat ids, and payments with a negative amount. They come from
  the data, not from the engine.
- **Same data.** After each run, every one of the 151 relations was summarised by
  a row count and two whole-row checksums. 147 relations match exactly across all
  six runs. Four aggregates (`agg_tpcds_basket_size`, `agg_tpcds_customer_rfm`,
  `agg_wb_seasonality`, `agg_wb_user_ltv`) differ from run to run, but they
  differ between two runs of Core and between two runs of v2 just as much as
  between Core and v2. They depend on floating point summation order or on how
  ties are broken, so they are not stable under either engine and say nothing
  about the difference between them.

## What this does and does not show

- It shows that dbt v2 builds a 553-node project on Databricks with the same
  result as Core, and that its parsing, compiling and package resolution are 6 to
  11 times faster.
- It does not show that v2 makes a warehouse-bound build much faster. It saved
  about 18 seconds of 232 here, all of it overhead outside the warehouse.
- Three runs per engine, on one day, on a free-tier warehouse whose performance
  can change. Treat the build figure as indicative.
- Not measured: a full refresh, projects of other sizes, `dbt-oss` (the
  Apache-2.0 distribution of v2), dbt Core with `--use-v2-parser`, and the native
  `dbt_task` job type. The last cannot run v2, so it could not be part of a
  same-runner comparison.

## Reproducing it

`infra/bench.tf` creates one job per engine. Trigger one with run-time
parameters, for example:

```bash
databricks jobs run-now --no-wait --json '{
  "job_id": <job id from `terraform output dbt_job_ids`>,
  "python_params": ["--engine", "v2",
    "--http-path", "/sql/1.0/warehouses/<warehouse id>",
    "--catalog", "dev_lakehouse", "--threads", "8",
    "--command", "deps", "--command", "parse", "--command", "parse",
    "--command", "compile", "--command", "build", "--report"]
}'
```

The runner prints `RESULT`, `NODES`, `WAREHOUSE` and `PARITY` lines in the run
output. Run one job at a time, and put nothing else on the warehouse while it
runs, or the warehouse figures will include that work.
