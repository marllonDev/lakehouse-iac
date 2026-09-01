# Databricks notebook source
"""
Consumes the Wikimedia EventStreams firehose and lands raw events as JSON Lines
files in a Unity Catalog volume.

This is the one part of the pipeline dbt cannot do: dbt has no HTTP client and
no long-running process. Everything downstream of the volume is dbt.

The stream is Server-Sent Events over a single long-lived HTTP connection, so
this task holds that connection open and flushes a file every `batch_seconds`.
Each file is written once and never modified, which is exactly what Auto Loader
in the downstream streaming table expects: it tracks which files it has already
read, so re-running is cheap and never double-counts.

Two modes, selected by `max_seconds`:

  triggered  (max_seconds > 0)  run for a bounded window, then exit. Paired with
                                a scheduled job, this gives near-real-time
                                ingestion at a predictable cost.
  continuous (max_seconds = 0)  never exit. Paired with a continuous job, this
                                is true real-time — and burns compute 24/7.

Parameters are read as Databricks widgets so the job can set them.
"""

import json
import os
import time
import urllib.request
import uuid

STREAM_URL = "https://stream.wikimedia.org/v2/stream/recentchange"

# Wikimedia asks every client to identify itself. An anonymous high-volume
# consumer is liable to be blocked.
USER_AGENT = "lakehouse-iac/0.1 (https://github.com/marllonDev/lakehouse-iac)"

# COMMAND ----------

dbutils.widgets.text("volume_path", "/Volumes/dev_lakehouse/raw/landing/wikipedia")
dbutils.widgets.text("batch_seconds", "60")
dbutils.widgets.text("max_seconds", "300")
dbutils.widgets.text("wikis", "enwiki,ptwiki")

volume_path = dbutils.widgets.get("volume_path")
batch_seconds = int(dbutils.widgets.get("batch_seconds"))
max_seconds = int(dbutils.widgets.get("max_seconds"))
wikis = {w.strip() for w in dbutils.widgets.get("wikis").split(",") if w.strip()}

# COMMAND ----------


def flush(buffer, volume_path):
    """Write one batch as a single immutable JSON Lines file.

    The filename carries a UUID rather than only a timestamp: two batches can
    land in the same second, and Auto Loader identifies files by name, so a
    collision would silently drop a batch.
    """
    if not buffer:
        return None

    name = f"{time.strftime('%Y%m%dT%H%M%S')}-{uuid.uuid4().hex[:8]}.json"
    path = f"{volume_path}/{name}"

    with open(path, "w", encoding="utf-8") as handle:
        for event in buffer:
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")

    return path


def consume(volume_path, batch_seconds, max_seconds, wikis):
    # Terraform creates the volume, but not the directories inside it. Writing
    # to a path whose parent does not exist fails with FileNotFoundError rather
    # than creating it, so make the target explicitly.
    os.makedirs(volume_path, exist_ok=True)

    request = urllib.request.Request(STREAM_URL, headers={"User-Agent": USER_AGENT})

    buffer = []
    started = time.time()
    last_flush = started
    files, events = 0, 0

    with urllib.request.urlopen(request, timeout=90) as stream:
        for raw_line in stream:
            if raw_line.startswith(b"data: "):
                try:
                    event = json.loads(raw_line[6:])
                except json.JSONDecodeError:
                    # A truncated frame is not worth failing the whole run over.
                    continue

                if not wikis or event.get("wiki") in wikis:
                    buffer.append(event)

            now = time.time()

            if now - last_flush >= batch_seconds:
                written = flush(buffer, volume_path)
                if written:
                    files += 1
                    events += len(buffer)
                    print(f"wrote {len(buffer):5d} events -> {written}")
                buffer = []
                last_flush = now

            if max_seconds and now - started >= max_seconds:
                break

    written = flush(buffer, volume_path)
    if written:
        files += 1
        events += len(buffer)
        print(f"wrote {len(buffer):5d} events -> {written}")

    return files, events


files, events = consume(volume_path, batch_seconds, max_seconds, wikis)
summary = f"files={files} events={events}"
print(summary)

# COMMAND ----------

dbutils.notebook.exit(summary)
