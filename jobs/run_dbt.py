"""Runs dbt, either engine, inside a Databricks serverless job.

The dbt_task job type only supports dbt Core with the dbt-databricks package, so
this script stands in for it, and it is the one runner both engines share: a
comparison of dbt Core and dbt v2 is only fair when everything except the engine
is identical. It does these things and nothing else:

1. Authenticates with the job's own identity through the Databricks SDK, so no
   personal access token and no secret file is ever needed.
2. Writes a throwaway profiles.yml that reads every connection value from
   environment variables, including the token, which is never written to disk.
3. Runs each requested dbt command in order against the transform/ project of
   the checkout this script came from, stopping at the first failure.
4. Prints one JSON line per report: RESULT (duration of every command), NODES
   (what the last build did, node by node), WAREHOUSE (what the warehouse did
   during the run) and PARITY (a checksum of every relation dbt built).

The dbt distribution itself is not installed here: the job environment pins it,
so the version that ran is always the one Terraform declares.
"""

import argparse
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PROFILE = """\
lakehouse:
  target: job
  outputs:
    job:
      type: databricks
      host: "{{{{ env_var('DBT_DATABRICKS_HOST') }}}}"
      http_path: "{{{{ env_var('DBT_DATABRICKS_HTTP_PATH') }}}}"
      catalog: "{{{{ env_var('DBT_CATALOG') }}}}"
      schema: {schema}
{auth}      threads: {threads}
"""

# dbt v2 accepts only oauth or token for auth_type, so it has to be spelled out.
# dbt Core takes the token from the token key alone.
AUTH = {
    "v2": '      auth_type: token\n      token: "{{ env_var(\'DBT_DATABRICKS_TOKEN\') }}"\n',
    "core": '      token: "{{ env_var(\'DBT_DATABRICKS_TOKEN\') }}"\n',
}


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--engine", choices=sorted(AUTH), required=True, help="Which dbt this environment installs")
    parser.add_argument("--http-path", required=True, help="SQL warehouse HTTP path")
    parser.add_argument("--catalog", required=True, help="Unity Catalog catalog dbt writes into")
    parser.add_argument("--schema", default="staging", help="Default schema in the generated profile")
    parser.add_argument("--threads", type=int, default=8, help="dbt threads; both engines run with the same number")
    parser.add_argument(
        "--command",
        action="append",
        required=True,
        help='A dbt command without the executable, e.g. "build --select marts". Repeatable.',
    )
    parser.add_argument(
        "--report",
        action="store_true",
        help="After the commands, print the NODES, WAREHOUSE and PARITY reports",
    )
    return parser.parse_args()


def find_dbt():
    found = shutil.which("dbt") or str(Path(sys.executable).parent / "dbt")
    if not Path(found).exists():
        sys.exit("dbt executable not found; the job environment must install the dbt distribution")
    return found


def run(cmd, env, secret):
    """Run a command, streaming its output with the token scrubbed out of it."""
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    for line in proc.stdout:
        print(line.replace(secret, "***"), end="", flush=True)
    return proc.wait()


def node_report(project_dir):
    """Summarise target/run_results.json: the same build must touch the same nodes."""
    path = project_dir / "target" / "run_results.json"
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    nodes = sorted((r["unique_id"], r["status"]) for r in data["results"])
    by_status = {}
    for _, status in nodes:
        by_status[status] = by_status.get(status, 0) + 1
    times = sorted(((r["execution_time"], r["unique_id"]) for r in data["results"]), reverse=True)
    return {
        "nodes": len(nodes),
        "by_status": by_status,
        "digest": hashlib.sha256(json.dumps(nodes).encode()).hexdigest()[:16],
        "elapsed_time": round(data.get("elapsed_time", 0), 2),
        "sum_node_seconds": round(sum(t for t, _ in times), 2),
        "slowest": [[uid, round(t, 2)] for t, uid in times[:8]],
        "not_success": [[uid, s] for uid, s in nodes if s not in ("success", "pass")],
    }


def warehouse_report(workspace, warehouse_id, started_ms, ended_ms):
    """What the warehouse did in the window: statement count, time, and time it sat idle."""
    from databricks.sdk.service.sql import QueryFilter, TimeRange

    queries, page_token = [], None
    while True:
        page = workspace.query_history.list(
            filter_by=QueryFilter(
                warehouse_ids=[warehouse_id],
                query_start_time_range=TimeRange(start_time_ms=started_ms, end_time_ms=ended_ms),
            ),
            include_metrics=True,
            max_results=500,
            page_token=page_token,
        )
        queries += page.res or []
        page_token = page.next_page_token
        if not page.has_next_page or not page_token:
            break
    spans = sorted(
        (q.query_start_time_ms, q.query_end_time_ms) for q in queries if q.query_start_time_ms and q.query_end_time_ms
    )
    busy, cursor_start, cursor_end = 0, None, None
    for start, end in spans:
        if cursor_end is None or start > cursor_end:
            if cursor_end is not None:
                busy += cursor_end - cursor_start
            cursor_start, cursor_end = start, end
        else:
            cursor_end = max(cursor_end, end)
    if cursor_end is not None:
        busy += cursor_end - cursor_start
    metrics = [q.metrics for q in queries if q.metrics]
    return {
        "statements": len(queries),
        "window_seconds": round((ended_ms - started_ms) / 1000, 1),
        "busy_seconds": round(busy / 1000, 1),
        "sum_duration_seconds": round(sum(q.duration or 0 for q in queries) / 1000, 1),
        "sum_execution_seconds": round(sum(m.execution_time_ms or 0 for m in metrics) / 1000, 1),
        "sum_compilation_seconds": round(sum(m.compilation_time_ms or 0 for m in metrics) / 1000, 1),
    }


def parity_report(workspace, warehouse_id, catalog, schemas):
    """A row count and two whole-row checksums for every table and view in the schemas.

    bit_xor and a decimal sum are both order independent, so two engines that built
    the same rows agree even when the rows were written in a different order. A
    plain sum of the 64-bit hashes overflows under ANSI mode, hence the decimal.
    """
    listing = workspace.statement_execution.execute_statement(
        warehouse_id=warehouse_id,
        statement=(
            f"select table_schema, table_name from {catalog}.information_schema.tables "
            f"where table_schema in ({', '.join(repr(s) for s in schemas)}) order by 1, 2"
        ),
        wait_timeout="50s",
    )
    tables = [tuple(row) for row in (listing.result.data_array or [])]

    def checksum(table):
        schema, name = table
        result = workspace.statement_execution.execute_statement(
            warehouse_id=warehouse_id,
            statement=(
                "select count(*), bit_xor(xxhash64(*)), sum(cast(xxhash64(*) as decimal(38, 0))) "
                f"from {catalog}.{schema}.{name}"
            ),
            wait_timeout="50s",
        )
        row = result.result.data_array[0] if result.result and result.result.data_array else [None] * 3
        return f"{schema}.{name}", row

    with ThreadPoolExecutor(max_workers=8) as pool:
        return dict(pool.map(checksum, tables))


def main():
    args = parse_args()

    # A Databricks spark_python_task runs the script through exec(compile(...)),
    # which leaves __file__ undefined. The compiled code object still carries the
    # real path of the file inside the Git checkout.
    script = Path(main.__code__.co_filename).resolve()
    checkout_project = script.parents[1] / "transform"
    if not (checkout_project / "dbt_project.yml").exists():
        sys.exit(f"no dbt project at {checkout_project}; is this script running from a Git checkout?")

    # dbt writes logs/, target/ and dbt_packages/ next to the project, and the Git
    # checkout under /Workspace refuses directory creation from a native process
    # (os error 22). Run from a scratch copy on local disk instead.
    project_dir = Path(tempfile.mkdtemp(prefix="dbt-project-")) / "transform"
    shutil.copytree(
        checkout_project,
        project_dir,
        ignore=shutil.ignore_patterns("target", "dbt_packages", "logs", ".user.yml"),
    )

    # Imported late so --help works without the SDK installed.
    from databricks.sdk import WorkspaceClient

    workspace = WorkspaceClient()
    token = workspace.config.authenticate()["Authorization"].removeprefix("Bearer ")

    profiles_dir = Path(tempfile.mkdtemp(prefix="profiles-"))
    (profiles_dir / "profiles.yml").write_text(
        PROFILE.format(schema=args.schema, threads=args.threads, auth=AUTH[args.engine])
    )

    env = {
        **os.environ,
        "DBT_DATABRICKS_HOST": workspace.config.host.removeprefix("https://"),
        "DBT_DATABRICKS_HTTP_PATH": args.http_path,
        "DBT_DATABRICKS_TOKEN": token,
        "DBT_CATALOG": args.catalog,
        "DO_NOT_TRACK": "1",
    }

    dbt = find_dbt()
    common = ["--project-dir", str(project_dir), "--profiles-dir", str(profiles_dir)]

    results = []
    nodes = None
    started_ms = int(time.time() * 1000)
    run([dbt, "--version"], env, token)

    for command in args.command:
        started = time.time()
        code = run([dbt, *shlex.split(command), *common], env, token)
        entry = {"command": command, "rc": code, "seconds": round(time.time() - started, 1)}
        results.append(entry)
        if shlex.split(command)[0] in ("build", "run", "test", "seed", "snapshot"):
            nodes = node_report(project_dir)
        if code != 0:
            break
    ended_ms = int(time.time() * 1000)

    print("RESULT " + json.dumps({"engine": args.engine, "threads": args.threads, "commands": results}))

    if args.report:
        warehouse_id = args.http_path.rsplit("/", 1)[-1]
        print("NODES " + json.dumps(nodes))
        try:
            print("WAREHOUSE " + json.dumps(warehouse_report(workspace, warehouse_id, started_ms, ended_ms)))
        except Exception as error:  # the report is a bonus; never fail the run over it
            print("WAREHOUSE " + json.dumps({"error": str(error)[:300]}))
        try:
            print("PARITY " + json.dumps(parity_report(workspace, warehouse_id, args.catalog, ["staging", "marts"])))
        except Exception as error:
            print("PARITY " + json.dumps({"error": str(error)[:300]}))

    # Raise only on failure. A Databricks task treats any SystemExit as a failed
    # run, including sys.exit(0), so a successful run must simply return.
    if not all(r["rc"] == 0 for r in results):
        sys.exit(1)


if __name__ == "__main__":
    main()
