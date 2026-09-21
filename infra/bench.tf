# One job per dbt engine, identical in everything except the engine.
#
# dbt_task only supports dbt Core, so both engines run through the same Python
# task (jobs/run_dbt.py). Same runner, same serverless environment version, same
# git branch, same warehouse, same thread count: the only thing that differs
# between the two jobs is which dbt distribution the environment installs.
#
# The jobs have no schedule and no continuous trigger. Their default commands
# resolve packages and parse, which never touch the warehouse; real runs pass
# their own parameters at trigger time, for example:
#
#   databricks jobs run-now --no-wait --json \
#     '{"job_id": <id>, "python_params": ["--engine","v2","--http-path","...",
#       "--catalog","dev_lakehouse","--command","deps","--command","build","--report"]}'
#
# Run-time parameters replace the defaults below entirely.
locals {
  engines = {
    # Pinned to the version the native dbt_task job installs.
    core = { package = "dbt-databricks", version = var.dbt_databricks_version }

    # Exact pin: dbt v2 ships as a sdist that fetches its binaries when pip
    # builds it, so uv.lock alone cannot make two installs identical.
    v2 = { package = var.dbt_v2_package, version = var.dbt_v2_version }
  }
}

resource "databricks_job" "dbt" {
  for_each = local.engines

  name        = "${var.environment}-${var.project}-dbt-${each.key}"
  description = "Runs dbt (${each.key}) through jobs/run_dbt.py. Manual trigger only."

  git_source {
    url      = var.git_repo_url
    provider = "gitHub"
    branch   = var.git_branch
  }

  max_concurrent_runs = 1
  timeout_seconds     = 3600

  environment {
    environment_key = "dbt"

    spec {
      environment_version = var.dbt_environment_version
      dependencies        = ["${each.value.package}==${each.value.version}"]
    }
  }

  task {
    task_key        = "dbt"
    environment_key = "dbt"

    spark_python_task {
      python_file = "jobs/run_dbt.py"
      source      = "GIT"

      parameters = [
        "--engine", each.key,
        "--http-path", "/sql/1.0/warehouses/${data.databricks_sql_warehouse.this.id}",
        "--catalog", local.catalog_name,
        "--schema", "staging",
        "--command", "deps",
        "--command", "parse",
      ]
    }
  }

  depends_on = [databricks_schema.this]
}

# The spike job was renamed into the shared resource; keep its history.
moved {
  from = databricks_job.dbt_v2_spike
  to   = databricks_job.dbt["v2"]
}
