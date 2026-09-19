"""Runs dbt v2 inside a Databricks serverless job.

The dbt_task job type only supports dbt Core with the dbt-databricks package, so
this script stands in for it. It does four things and nothing else:

1. Authenticates with the job's own identity through the Databricks SDK, so no
   personal access token and no secret file is ever needed.
2. Writes a throwaway profiles.yml that reads every connection value from
   environment variables, including the token, which is never written to disk.
3. Runs each requested dbt command in order against the transform/ project of
   the checkout this script came from, stopping at the first failure.
4. Prints a one-line JSON summary with the duration of every command.

The dbt distribution itself is not installed here: the job environment pins it,
so the version that ran is always the one Terraform declares.
"""

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
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
      auth_type: token
      token: "{{{{ env_var('DBT_DATABRICKS_TOKEN') }}}}"
      threads: 4
"""


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--http-path", required=True, help="SQL warehouse HTTP path")
    parser.add_argument("--catalog", required=True, help="Unity Catalog catalog dbt writes into")
    parser.add_argument("--schema", default="staging", help="Default schema in the generated profile")
    parser.add_argument(
        "--command",
        action="append",
        required=True,
        help='A dbt command without the executable, e.g. "build --select marts". Repeatable.',
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


def main():
    args = parse_args()

    # A Databricks spark_python_task runs the script through exec(compile(...)),
    # which leaves __file__ undefined. The compiled code object still carries the
    # real path of the file inside the Git checkout.
    script = Path(main.__code__.co_filename).resolve()
    project_dir = script.parents[1] / "transform"
    if not (project_dir / "dbt_project.yml").exists():
        sys.exit(f"no dbt project at {project_dir}; is this script running from a Git checkout?")

    # Imported late so --help works without the SDK installed.
    from databricks.sdk import WorkspaceClient

    workspace = WorkspaceClient()
    token = workspace.config.authenticate()["Authorization"].removeprefix("Bearer ")

    profiles_dir = Path(tempfile.mkdtemp(prefix="profiles-"))
    (profiles_dir / "profiles.yml").write_text(PROFILE.format(schema=args.schema))

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
    run([dbt, "--version"], env, token)

    for command in args.command:
        started = time.time()
        code = run([dbt, *shlex.split(command), *common], env, token)
        results.append({"command": command, "rc": code, "seconds": round(time.time() - started, 1)})
        if code != 0:
            break

    print("RESULT " + json.dumps(results))
    sys.exit(0 if all(r["rc"] == 0 for r in results) else 1)


if __name__ == "__main__":
    main()
