# Authentication is resolved by the provider's default credential chain, which
# picks up the Databricks CLI profile named by DATABRICKS_CONFIG_PROFILE (or the
# DATABRICKS_HOST / DATABRICKS_TOKEN pair). No secrets live in this repository.
provider "databricks" {}
