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

output "wikipedia_ingest_job_id" {
  description = "Always-on job that holds the Wikimedia firehose connection and lands files."
  value       = databricks_job.wikipedia_ingest.id
}

output "wikipedia_ingest_job_url" {
  description = "Direct link to the ingestion job in the Databricks UI."
  value       = databricks_job.wikipedia_ingest.url
}

output "wikipedia_transform_job_id" {
  description = "Scheduled job that rebuilds the Wikimedia streaming models."
  value       = databricks_job.wikipedia_transform.id
}

output "wikipedia_transform_job_url" {
  description = "Direct link to the transform job in the Databricks UI."
  value       = databricks_job.wikipedia_transform.url
}
