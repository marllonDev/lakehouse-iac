locals {
  landing_volume_path = "/Volumes/${local.catalog_name}/raw/landing"
  wikipedia_path      = "${local.landing_volume_path}/wikipedia"

  # In continuous mode the ingestion task must never exit on its own — the job
  # itself owns the lifecycle and restarts the task if it dies. max_seconds=0
  # is the script's signal for "run forever".
  ingest_max_seconds = var.streaming_mode == "continuous" ? 0 : var.ingest_window_seconds
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

# Ingest, then transform. Two tasks rather than one because they have genuinely
# different shapes: the first holds a network connection open and writes files,
# the second is a batch SQL run against a warehouse. Splitting them means a dbt
# failure does not lose the events already landed.
resource "databricks_job" "wikipedia" {
  name        = "${var.environment}-${var.project}-wikipedia"
  description = "Consumes the Wikimedia EventStreams firehose, then rebuilds the dbt models on top of it."

  git_source {
    url      = var.git_repo_url
    provider = "gitHub"
    branch   = var.git_branch
  }

  # Only one of these blocks is ever active. In continuous mode the job restarts
  # the task as soon as it exits, so a dropped SSE connection self-heals.
  dynamic "schedule" {
    for_each = var.streaming_mode == "triggered" ? [1] : []

    content {
      quartz_cron_expression = var.ingest_schedule_cron
      timezone_id            = "UTC"
    }
  }

  dynamic "continuous" {
    for_each = var.streaming_mode == "continuous" ? [1] : []

    content {
      pause_status = "UNPAUSED"
    }
  }

  # Overlapping runs would land duplicate files and race the dbt build.
  max_concurrent_runs = 1

  environment {
    environment_key = "default"

    spec {
      client = "3"
    }
  }

  task {
    task_key        = "ingest"
    environment_key = "default"

    notebook_task {
      notebook_path = "ingest/wikipedia_stream"
      source        = "GIT"

      base_parameters = {
        volume_path   = local.wikipedia_path
        batch_seconds = tostring(var.ingest_batch_seconds)
        max_seconds   = tostring(local.ingest_max_seconds)
        wikis         = var.wikis
      }
    }
  }

  task {
    task_key        = "transform"
    environment_key = "default"

    depends_on {
      task_key = "ingest"
    }

    dbt_task {
      project_directory  = "transform"
      profiles_directory = "transform"
      warehouse_id       = data.databricks_sql_warehouse.this.id

      commands = [
        "dbt deps",
        "dbt build --select st_wikipedia_edits+",
      ]
    }
  }

  depends_on = [databricks_volume.landing]
}
