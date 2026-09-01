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

variable "streaming_mode" {
  description = <<-EOT
    How the Wikimedia ingestion job runs.

    "triggered"  — the job runs on a schedule, each run consuming the firehose
                   for `ingest_window_seconds` and then exiting. Latency is
                   roughly one schedule interval; compute cost is bounded and
                   predictable.

    "continuous" — the job never exits and holds the stream open. True real
                   time, at the cost of compute running 24/7. On Free Edition
                   that will consume the account's limited serverless
                   allowance quickly, so it is not the default.
  EOT
  type        = string
  default     = "triggered"

  validation {
    condition     = contains(["triggered", "continuous"], var.streaming_mode)
    error_message = "streaming_mode must be one of: triggered, continuous."
  }
}

variable "ingest_schedule_cron" {
  description = "Quartz cron for the ingestion job in triggered mode. Default is every 5 minutes."
  type        = string
  default     = "0 0/5 * * * ?"
}

variable "ingest_window_seconds" {
  description = <<-EOT
    How long a triggered run consumes the firehose before exiting. Should be
    comfortably shorter than the schedule interval so runs never overlap.
    Ignored in continuous mode, where the task is told to run forever.
  EOT
  type        = number
  default     = 180
}

variable "ingest_batch_seconds" {
  description = "How often the ingestion task flushes a landing file."
  type        = number
  default     = 60
}

variable "wikis" {
  description = "Comma-separated Wikimedia wiki codes to keep. Empty string keeps every wiki."
  type        = string
  default     = "enwiki,ptwiki"
}
