locals {
  landing_volume_path = "/Volumes/${local.catalog_name}/raw/landing"
  wikipedia_path      = "${local.landing_volume_path}/wikipedia"
}

# The landing zone. Files written here are immutable; the downstream streaming
# table tracks which ones it has already read.
resource "databricks_volume" "landing" {
  name         = "landing"
  catalog_name = local.catalog_name
  schema_name  = databricks_schema.this["raw"].name
  volume_type  = "MANAGED"
  comment      = "Raw event files landed by streaming ingestion, one file per flush."

  depends_on = [databricks_schema.this]
}

# Ingestion and transformation are two independent jobs, not two tasks in one
# job. An earlier version chained them with depends_on so transform only ran
# after ingest finished — which meant an always-on ingest task (needed for low
# latency) could never hand off, because it never finishes. Splitting them
# removes that coupling entirely: ingest just holds the connection open and
# writes files, forever; transform runs on its own short cycle and picks up
# whatever exists via Auto Loader's file-level checkpoint, regardless of what
# ingest is doing at that moment.
resource "databricks_job" "wikipedia_ingest" {
  name        = "${var.environment}-${var.project}-wikipedia-ingest"
  description = "Holds the Wikimedia EventStreams connection open and lands events as files. Runs continuously; pause with ingest_pause_status."

  git_source {
    url      = var.git_repo_url
    provider = "gitHub"
    branch   = var.git_branch
  }

  continuous {
    pause_status = var.ingest_pause_status
  }

  environment {
    environment_key = "ingest"

    spec {
      client = "3"
    }
  }

  task {
    task_key        = "ingest"
    environment_key = "ingest"

    notebook_task {
      notebook_path = "ingest/wikipedia_stream"
      source        = "GIT"

      base_parameters = {
        volume_path   = local.wikipedia_path
        batch_seconds = tostring(var.ingest_batch_seconds)
        # 0 tells the script to never exit. There is no windowed variant any
        # more: an ingestion job that stops on its own is exactly the coupling
        # this split was written to remove.
        max_seconds = "0"
        wikis       = var.wikis
      }
    }
  }

  depends_on = [databricks_volume.landing]
}

resource "databricks_job" "wikipedia_transform" {
  name        = "${var.environment}-${var.project}-wikipedia-transform"
  description = "Rebuilds the Wikimedia streaming models. Scheduled independently of ingestion."

  git_source {
    url      = var.git_repo_url
    provider = "gitHub"
    branch   = var.git_branch
  }

  schedule {
    quartz_cron_expression = var.dbt_schedule_cron
    timezone_id            = "UTC"
    # Pausing ingestion with no equivalent here would leave this firing every
    # few minutes to rebuild a streaming table that never receives new files —
    # short, but not free. The two are meant to be paused together.
    pause_status = var.ingest_pause_status
  }

  # A run that overlaps the previous one would race the same MERGE; dropping
  # it is correct here; MAX_CONCURRENT_RUNS_EXCEEDED in the run history is the
  # signal that dbt_schedule_cron needs to be widened.
  max_concurrent_runs = 1

  environment {
    environment_key = "dbt"

    spec {
      client = "3"

      # Serverless job compute starts empty: without this the task fails with
      # "dbt: command not found". Pinned to match pyproject.toml so a run on
      # Databricks resolves the same version as a run on a laptop.
      dependencies = ["dbt-databricks==${var.dbt_databricks_version}"]
    }
  }

  task {
    task_key        = "transform"
    environment_key = "dbt"

    dbt_task {
      project_directory  = "transform"
      profiles_directory = "transform"
      warehouse_id       = data.databricks_sql_warehouse.this.id

      # A dbt task generates its own profile and ignores the one in the repo,
      # so the catalog has to be declared here. Without it dbt falls back to the
      # legacy Hive metastore and fails with UC_HIVE_METASTORE_DISABLED_EXCEPTION
      # on any Unity Catalog workspace.
      catalog = local.catalog_name
      schema  = "staging"

      commands = [
        "dbt deps",
        "dbt build --select st_wikipedia_edits+",
      ]
    }
  }

  depends_on = [databricks_schema.this]
}
