data "databricks_current_user" "me" {}

data "databricks_sql_warehouse" "this" {
  name = var.sql_warehouse_name
}

locals {
  catalog_name = "${var.environment}_${var.project}"

  common_properties = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Free Edition rejects the Unity Catalog create-catalog REST call that the
# databricks_catalog resource makes, so the catalog is bootstrapped over SQL
# instead. See scripts/uc-catalog.sh for the full explanation. Everything the
# API does support — schemas, grants — stays on native resources below.
resource "terraform_data" "catalog" {
  input = {
    name         = local.catalog_name
    script       = abspath("${path.module}/../scripts/uc-catalog.sh")
    profile      = var.databricks_profile
    warehouse_id = data.databricks_sql_warehouse.this.id
  }

  provisioner "local-exec" {
    command = "'${self.input.script}' create ${self.input.name}"

    environment = {
      DATABRICKS_CONFIG_PROFILE = self.input.profile
      WAREHOUSE_ID              = self.input.warehouse_id
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "'${self.input.script}' drop ${self.input.name}"

    environment = {
      DATABRICKS_CONFIG_PROFILE = self.input.profile
      WAREHOUSE_ID              = self.input.warehouse_id
    }
  }
}

# Terraform owns the containers — catalog, schemas, grants. dbt owns the
# relations inside them. Holding that line is what keeps the two tools from
# fighting over the same Unity Catalog objects.
resource "databricks_schema" "this" {
  for_each = var.schemas

  catalog_name  = local.catalog_name
  name          = each.key
  comment       = each.value.comment
  properties    = local.common_properties
  force_destroy = true

  depends_on = [terraform_data.catalog]
}

resource "databricks_grants" "catalog" {
  catalog = local.catalog_name

  grant {
    principal  = data.databricks_current_user.me.user_name
    privileges = ["ALL_PRIVILEGES"]
  }

  depends_on = [terraform_data.catalog]
}
