# The TPC-H batch models have no job of their own: until now they were only ever
# built by running dbt from a laptop. This job runs them on Databricks instead,
# so nothing about the project has to execute on a developer machine.
#
# It has no schedule and no continuous trigger, so it never runs on its own —
# it is started by hand with `databricks jobs run-now`. Every streaming model is
# excluded: those belong to wikipedia-transform and depend on files that only
# the ingest job produces.
resource "databricks_job" "tpch_batch" {
  name        = "${var.environment}-${var.project}-tpch-batch"
  description = "Builds the TPC-H batch models (staging views and the dimensional marts). Manual trigger only."

  git_source {
    url      = var.git_repo_url
    provider = "gitHub"
    branch   = var.git_branch
  }

  max_concurrent_runs = 1

  environment {
    environment_key = "dbt"

    spec {
      client = "3"

      # Serverless job compute starts empty: without this the task fails with
      # "dbt: command not found". Same pin as the transform job.
      dependencies = ["dbt-databricks==${var.dbt_databricks_version}"]
    }
  }

  task {
    task_key        = "build"
    environment_key = "dbt"

    dbt_task {
      project_directory  = "transform"
      profiles_directory = "transform"
      warehouse_id       = data.databricks_sql_warehouse.this.id

      # A dbt task generates its own profile and ignores the one in the repo, so
      # the catalog has to be declared here (see streaming.tf).
      catalog = local.catalog_name
      schema  = "staging"

      commands = [
        "dbt deps",
        # `st_wikipedia_edits+` is the streaming table and everything built on
        # it; excluding it leaves exactly the TPC-H models.
        "dbt build --exclude st_wikipedia_edits+",
      ]
    }
  }

  depends_on = [databricks_schema.this]
}
