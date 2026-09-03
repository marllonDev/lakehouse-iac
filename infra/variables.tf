variable "environment" {
  description = "Deployment environment. Becomes the Unity Catalog catalog name prefix."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "project" {
  description = "Project slug used to name and tag every managed resource."
  type        = string
  default     = "lakehouse"
}

variable "databricks_profile" {
  description = "Databricks CLI profile the catalog bootstrap script authenticates with."
  type        = string
  default     = "FREE"
}

variable "sql_warehouse_name" {
  description = <<-EOT
    Existing SQL warehouse used by dbt and by the catalog bootstrap script.
    Free Edition ships exactly one warehouse and refuses to create more, so this
    is looked up rather than managed.
  EOT
  type        = string
  default     = "Serverless Starter Warehouse"
}

variable "schemas" {
  description = "Medallion schemas created inside the catalog, keyed by schema name."
  type = map(object({
    comment = string
  }))

  default = {
    raw = {
      comment = "Landing zone. Holds the volume that streaming ingestion writes into."
    }
    staging = {
      comment = "One dbt view per source table: renamed, recast, lightly cleaned."
    }
    marts = {
      comment = "Business-facing dimensional models consumed by BI and analysts."
    }
  }
}

variable "git_repo_url" {
  description = "HTTPS URL of the repository the dbt job clones at run time."
  type        = string
  default     = "https://github.com/marllonDev/lakehouse-iac"
}

variable "git_branch" {
  description = "Branch the dbt job runs from."
  type        = string
  default     = "main"
}

variable "ingest_pause_status" {
  description = <<-EOT
    Controls whether both streaming jobs are running. Applied to both
    wikipedia-ingest and wikipedia-transform together: pausing one without the
    other leaves the transform job firing every few minutes to rebuild a
    streaming table that never receives a new file.

    "UNPAUSED" — ingestion holds the Wikimedia firehose connection open
                 permanently, restarting automatically if it drops; transform
                 runs on its schedule.
    "PAUSED"   — both jobs exist but do not run. Use this to stop consuming
                 Free Edition's serverless allowance between demos, without
                 destroying anything or losing what has already landed.
  EOT
  type        = string
  default     = "UNPAUSED"

  validation {
    condition     = contains(["UNPAUSED", "PAUSED"], var.ingest_pause_status)
    error_message = "ingest_pause_status must be one of: UNPAUSED, PAUSED."
  }
}

variable "ingest_batch_seconds" {
  description = "How often the ingestion task flushes a landing file. This is the floor on end-to-end latency: an edit cannot become a row before its batch is flushed."
  type        = number
  default     = 60
}

variable "dbt_schedule_cron" {
  description = <<-EOT
    Quartz cron for the transform job, which rebuilds the streaming models on
    a fixed schedule independent of ingestion. Auto Loader tracks which files
    it has already read, so running this on any cadence is safe — it always
    picks up whatever has landed since the last run.

    The interval must exceed one run's duration or overlapping triggers are
    dropped with MAX_CONCURRENT_RUNS_EXCEEDED rather than queued — measured
    directly: a three-minute default did exactly this on its second trigger.
    Two real runs against this workspace: 114.97s once the job's environment
    was warm, 254.70s on the very first run against a cold one (fresh
    dependency install, cold git checkout). Five minutes clears both with
    margin; narrower is possible but should be re-validated against a few
    more real runs first, not assumed.
  EOT
  type        = string
  default     = "0 0/5 * * * ?"
}

variable "wikis" {
  description = "Comma-separated Wikimedia wiki codes to keep. Empty string keeps every wiki."
  type        = string
  default     = "enwiki,ptwiki"
}

variable "dbt_databricks_version" {
  description = <<-EOT
    Version of dbt-databricks installed into the job's serverless environment.
    Keep this in step with the pin in pyproject.toml so a run on Databricks and
    a run on a laptop resolve the same adapter.
  EOT
  type        = string
  default     = "1.12.4"
}
