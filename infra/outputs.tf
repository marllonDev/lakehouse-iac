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

output "tpch_batch_job_id" {
  description = "Manually triggered job that builds the TPC-H batch models."
  value       = databricks_job.tpch_batch.id
}

output "tpch_batch_job_url" {
  description = "Direct link to the TPC-H batch job in the Databricks UI."
  value       = databricks_job.tpch_batch.url
}

output "dbt_job_ids" {
  description = "Job id of each dbt engine's benchmark job, keyed by engine."
  value       = { for engine, job in databricks_job.dbt : engine => job.id }
}

output "dbt_job_urls" {
  description = "Direct link to each dbt engine's benchmark job in the Databricks UI."
  value       = { for engine, job in databricks_job.dbt : engine => job.url }
}
