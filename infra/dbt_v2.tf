# Spike: run dbt v2 on Databricks.
#
# dbt_task only supports dbt Core, so this job uses a Python task
# (jobs/run_dbt_v2.py) that runs the dbt v2 executable itself, authenticated with
# the job's own identity. Nothing here touches the production jobs.
#
# It has no schedule and no continuous trigger. Its default commands only
# resolve packages and parse, which never touch the warehouse; real runs pass
# their own commands at trigger time, for example:
#
#   databricks jobs run-now <id> --python-params \
#     '["--http-path","...","--catalog","dev_lakehouse","--command","deps","--command","build --exclude st_wikipedia_edits+"]'
#
# Run-time parameters replace the defaults below entirely.
resource "databricks_job" "dbt_v2_spike" {
  name        = "${var.environment}-${var.project}-dbt-v2-spike"
  description = "Spike: runs dbt v2 through a Python task. Manual trigger only."

  git_source {
    url      = var.git_repo_url
    provider = "gitHub"
    branch   = var.dbt_v2_git_branch
  }

  max_concurrent_runs = 1
  timeout_seconds     = 1800

  environment {
    environment_key = "dbt_v2"

    spec {
      # Newer than the production jobs on purpose: this is the spike, and the
      # question it answers includes whether dbt v2 is happy on the latest base
      # environment. `client` is the legacy name for the same setting.
      environment_version = var.dbt_v2_environment_version

      # Exact pin: dbt v2 ships as a sdist that fetches its binaries when pip
      # builds it, so uv.lock alone cannot make two installs identical. Pinning
      # the version here is what keeps a run reproducible.
      dependencies = ["${var.dbt_v2_package}==${var.dbt_v2_version}"]
    }
  }

  task {
    task_key        = "dbt_v2"
    environment_key = "dbt_v2"

    spark_python_task {
      python_file = "jobs/run_dbt_v2.py"
      source      = "GIT"

      parameters = [
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
