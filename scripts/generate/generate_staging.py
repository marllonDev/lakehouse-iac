#!/usr/bin/env python3
"""Generates the dbt staging layer for the Databricks samples datasets.

Reads scripts/generate/samples_schema.json, a snapshot of the tables' columns, so
it needs no warehouse connection, and writes:

  transform/models/staging/<dataset>/_<dataset>__sources.yml
  transform/models/staging/<dataset>/_<dataset>__models.yml
  transform/models/staging/<dataset>/stg_<dataset>__<table>.sql

One staging model per source table, and nothing else: a rename, never a join.
TPC-DS columns carry a table prefix (ss_sold_date_sk), which is stripped so
that later models read naturally. The output is committed; rerunning this
script must leave the working tree unchanged.

Usage: python3 scripts/generate/generate_staging.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "transform" / "models" / "staging"
SNAPSHOT = json.loads((Path(__file__).parent / "samples_schema.json").read_text())
COLUMNS = SNAPSHOT["columns"]

# DESCRIBE TABLE repeats a partition column under "# Partition Information", and a
# select that lists it twice fails with COLUMN_ALREADY_EXISTS. The snapshot is
# already clean; this keeps a future recapture from reintroducing the bug.
for _table, _cols in COLUMNS.items():
    _seen = set()
    COLUMNS[_table] = [c for c in _cols if not (c[0] in _seen or _seen.add(c[0]))]

# Primary keys, by table. Composite keys are tuples. TPC-DS comes from a generator,
# so its keys are clean and tested at error severity. The Wanderbricks tables are
# closer to real data, so a broken key there is reported without stopping the build.
TPCDS_KEYS = {
    "call_center": ("cc_call_center_sk",),
    "catalog_page": ("cp_catalog_page_sk",),
    "catalog_returns": ("cr_item_sk", "cr_order_number"),
    "catalog_sales": ("cs_item_sk", "cs_order_number"),
    "customer": ("c_customer_sk",),
    "customer_address": ("ca_address_sk",),
    "customer_demographics": ("cd_demo_sk",),
    "date_dim": ("d_date_sk",),
    "household_demographics": ("hd_demo_sk",),
    "income_band": ("ib_income_band_sk",),
    "inventory": ("inv_date_sk", "inv_item_sk", "inv_warehouse_sk"),
    "item": ("i_item_sk",),
    "promotion": ("p_promo_sk",),
    "reason": ("r_reason_sk",),
    "ship_mode": ("sm_ship_mode_sk",),
    "store": ("s_store_sk",),
    "store_returns": ("sr_item_sk", "sr_ticket_number"),
    "store_sales": ("ss_item_sk", "ss_ticket_number"),
    "time_dim": ("t_time_sk",),
    "warehouse": ("w_warehouse_sk",),
    "web_page": ("wp_web_page_sk",),
    "web_returns": ("wr_item_sk", "wr_order_number"),
    "web_sales": ("ws_item_sk", "ws_order_number"),
    "web_site": ("web_site_sk",),
}

WANDERBRICKS_KEYS = {
    "amenities": ("amenity_id",),
    "booking_updates": ("booking_update_id",),
    "bookings": ("booking_id",),
    "clickstream": (),
    "countries": ("country_code",),
    "customer_support_logs": ("ticket_id",),
    "destinations": ("destination_id",),
    "employees": ("employee_id",),
    "hosts": ("host_id",),
    "page_views": ("view_id",),
    "payments": ("payment_id",),
    "properties": ("property_id",),
    "property_amenities": ("property_id", "amenity_id"),
    "property_images": ("image_id",),
    "reviews": ("review_id",),
    "users": ("user_id",),
}

# ClickBench's hits table has 105 columns. Keep the ones the marts use, renamed.
CLICKBENCH_COLUMNS = [
    ("WatchID", "watch_id"),
    ("EventTime", "event_at"),
    ("EventDate", "event_date"),
    ("CounterID", "counter_id"),
    ("ClientIP", "client_ip"),
    ("RegionID", "region_id"),
    ("UserID", "user_id"),
    ("OS", "os_id"),
    ("UserAgent", "user_agent_id"),
    ("URL", "url"),
    ("Referer", "referer"),
    ("IsRefresh", "is_refresh"),
    ("ResolutionWidth", "resolution_width"),
    ("IsMobile", "is_mobile"),
    ("MobilePhoneModel", "mobile_phone_model"),
    ("SearchEngineID", "search_engine_id"),
    ("SearchPhrase", "search_phrase"),
    ("AdvEngineID", "adv_engine_id"),
    ("IsLink", "is_link"),
    ("IsDownload", "is_download"),
    ("IsNotBounce", "is_not_bounce"),
    ("TraficSourceID", "traffic_source_id"),
]


def prefix_of(table, columns):
    """The shared column prefix of a TPC-DS table, or '' when there is none."""
    first = columns[0][0]
    head = first.split("_")[0] + "_"
    if table == "web_site":
        head = "web_"
    return head if all(name.startswith(head) for name, _ in columns) else ""


def strip(name, prefix):
    return name[len(prefix):] if prefix else name


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def sources_yml(dataset, schema, description, tables):
    lines = ["version: 2", "", "sources:", f"  - name: {dataset}", "    description: >"]
    lines += [f"      {row}" for row in description]
    lines += ["    catalog: samples", f"    schema: {schema}", "", "    tables:"]
    lines += [f"      - name: {t}" for t in tables]
    return "\n".join(lines) + "\n"


def model_sql(source, table, select_lines):
    body = ",\n".join(f"        {line}" for line in select_lines)
    return (
        "with source as (\n\n"
        f"    select * from {{{{ source('{source}', '{table}') }}}}\n\n"
        "),\n\n"
        "renamed as (\n\n"
        "    select\n"
        f"{body}\n\n"
        "    from source\n\n"
        ")\n\n"
        "select * from renamed\n"
    )


def keyed_tests(keys, severity):
    """YAML fragments (model-level, column-level) that assert a primary key."""
    model_level, column_level = [], {}
    if len(keys) > 1:
        cols = "\n".join(f"                - {k}" for k in keys)
        model_level.append(
            "      - dbt_utils.unique_combination_of_columns:\n"
            "          arguments:\n"
            "              combination_of_columns:\n"
            f"{cols}" + (f"\n          config:\n            severity: {severity}" if severity != "error" else "")
        )
    for k in keys:
        tests = ["not_null"] if len(keys) > 1 else ["unique", "not_null"]
        column_level[k] = tests
    return model_level, column_level


def models_yml(entries, severity):
    """entries: list of (model_name, description, [key columns after renaming])."""
    out = ["version: 2", "", "models:"]
    for model, description, keys in entries:
        out += [f"  - name: {model}", f"    description: {description}"]
        model_level, column_level = keyed_tests(keys, severity)
        if model_level:
            out += ["    data_tests:"] + model_level
        if column_level:
            out += ["    columns:"]
            for column, tests in column_level.items():
                if severity == "error":
                    out += [f"      - name: {column}", f"        data_tests: [{', '.join(tests)}]"]
                else:
                    out += [f"      - name: {column}", "        data_tests:"]
                    for t in tests:
                        out += [f"          - {t}:", "              config:", f"                severity: {severity}"]
        out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


def generate_tpcds():
    tables = sorted(TPCDS_KEYS)
    entries = []
    for table in tables:
        cols = COLUMNS[f"tpcds_sf1.{table}"]
        prefix = prefix_of(table, cols)
        select = [f"{name} as {strip(name, prefix)}" if prefix else name for name, _ in cols]
        model = f"stg_tpcds__{table}"
        write(STAGING / "tpcds" / f"{model}.sql", model_sql("tpcds", table, select))
        keys = tuple(strip(k, prefix) for k in TPCDS_KEYS[table])
        entries.append((model, f"One row per {table.replace('_', ' ')} row in samples.tpcds_sf1, columns renamed without the table prefix.", keys))
    write(
        STAGING / "tpcds" / "_tpcds__sources.yml",
        sources_yml(
            "tpcds",
            "tpcds_sf1",
            ["TPC-DS at scale factor 1, shipped read-only in the Databricks samples", "catalog: a retail star schema with three sales channels."],
            tables,
        ),
    )
    write(STAGING / "tpcds" / "_tpcds__models.yml", models_yml(entries, "error"))
    return len(tables)


def generate_wanderbricks():
    tables = sorted(WANDERBRICKS_KEYS)
    entries = []
    for table in tables:
        cols = COLUMNS[f"wanderbricks.{table}"]
        select = [name for name, _ in cols]
        model = f"stg_wanderbricks__{table}"
        write(STAGING / "wanderbricks" / f"{model}.sql", model_sql("wanderbricks", table, select))
        entries.append((model, f"One row per {table.replace('_', ' ')} row in samples.wanderbricks.", WANDERBRICKS_KEYS[table]))
    write(
        STAGING / "wanderbricks" / "_wanderbricks__sources.yml",
        sources_yml(
            "wanderbricks",
            "wanderbricks",
            ["A short-term rental marketplace shipped in the Databricks samples:", "bookings, payments, reviews, clickstream and support tickets."],
            tables,
        ),
    )
    write(STAGING / "wanderbricks" / "_wanderbricks__models.yml", models_yml(entries, "warn"))
    return len(tables)


def generate_clickbench():
    select = [f"{raw} as {clean}" for raw, clean in CLICKBENCH_COLUMNS]
    write(STAGING / "clickbench" / "stg_clickbench__hits.sql", model_sql("clickbench", "hits", select))
    write(
        STAGING / "clickbench" / "_clickbench__sources.yml",
        sources_yml(
            "clickbench",
            "clickbench",
            ["ClickBench's hits table, about 100 million web analytics events with 105", "columns, shipped in the Databricks samples."],
            ["hits"],
        ),
    )
    write(
        STAGING / "clickbench" / "_clickbench__models.yml",
        "version: 2\n\nmodels:\n  - name: stg_clickbench__hits\n"
        "    description: >\n      One row per web analytics event. Keeps the 22 of 105 columns the marts use,\n"
        "      renamed to snake case.\n    columns:\n      - name: watch_id\n        data_tests: [not_null]\n"
        "      - name: event_at\n        data_tests: [not_null]\n",
    )
    return 1


if __name__ == "__main__":
    counts = {"tpcds": generate_tpcds(), "wanderbricks": generate_wanderbricks(), "clickbench": generate_clickbench()}
    print("staging models written:", counts, "total", sum(counts.values()))
