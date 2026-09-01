{#
  dbt's default behaviour is to prefix custom schemas with the profile schema,
  producing names like "staging_marts". Terraform has already created the exact
  schemas we want, so use the custom name verbatim and fall back to the profile
  schema only when a model does not declare one.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
