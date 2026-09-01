output "catalog_name" {
  description = "Unity Catalog catalog that dbt writes into."
  value       = local.catalog_name
}

output "schema_names" {
  description = "Schemas created inside the catalog."
  value       = sort(keys(databricks_schema.this))
}

output "sql_warehouse_id" {
  description = "Warehouse dbt connects to."
  value       = data.databricks_sql_warehouse.this.id
}

output "dbt_http_path" {
  description = "Value for DATABRICKS_HTTP_PATH in the dbt profile."
  value       = "/sql/1.0/warehouses/${data.databricks_sql_warehouse.this.id}"
}

output "wikipedia_landing_path" {
  description = "Volume path the ingestion task writes into. Must match the dbt var of the same name."
  value       = local.wikipedia_path
}

output "wikipedia_job_id" {
  description = "Job that ingests the Wikimedia firehose and rebuilds the dbt models on top of it."
  value       = databricks_job.wikipedia.id
}

output "wikipedia_job_url" {
  description = "Direct link to the job in the Databricks UI."
  value       = databricks_job.wikipedia.url
}

output "streaming_mode" {
  description = "Whether ingestion runs on a schedule or holds the stream open continuously."
  value       = var.streaming_mode
}
