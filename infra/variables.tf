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
  description = <<-EOT
    Branch both dbt jobs clone at run time. They share one variable on purpose:
    comparing dbt Core with dbt v2 only means something if both run exactly the
    same code. Currently the feature branch; set it back to main once merged.
  EOT
  type        = string
  default     = "feat/dbt-v2-sail-spike"
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

variable "dbt_v2_package" {
  description = <<-EOT
    PyPI distribution of dbt v2 installed into the spike job's environment.
    "dbt" is the dbt Labs distribution (dbt license); "dbt-oss" is the Apache-2.0
    subset. Both connected to a Databricks SQL warehouse and parsed this
    project in the feasibility probe, so this is a licence choice, not a
    capability one, until a build proves otherwise.
  EOT
  type        = string
  default     = "dbt"

  validation {
    condition     = contains(["dbt", "dbt-oss"], var.dbt_v2_package)
    error_message = "dbt_v2_package must be one of: dbt, dbt-oss."
  }
}

variable "dbt_v2_version" {
  description = <<-EOT
    Exact version of dbt_v2_package. The two distributions do not share version
    numbers: dbt was 2.0.6 and dbt-oss 2.0.5 when this spike started. Never a
    range, because the package fetches binaries at install time and a range
    would let two runs of the same commit execute different dbt builds.
  EOT
  type        = string
  default     = "2.0.6"
}

variable "dbt_v2_environment_version" {
  description = <<-EOT
    Serverless environment version (base environment) of the dbt v2 spike job.
    Version 6 was released on 2026-09-03 with the same Python as version 3
    (3.12.3), a newer Ubuntu patch level, and Databricks Connect 19. The
    production and baseline jobs stay on version 3; only the spike moves.
  EOT
  type        = string
  default     = "6"
}
