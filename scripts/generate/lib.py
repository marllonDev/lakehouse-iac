"""Shared helpers for the model generators.

A model is a Model: its SQL, a description, the columns that make up its grain,
and the tests to assert per column. render_yml() turns a group of models into the
schema file that sits next to them, so a model and its tests are written once,
side by side, in the generator.
"""

from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / "transform" / "models"


@dataclass
class Model:
    name: str
    sql: str
    description: str
    grain: tuple = ()  # columns that together identify one row; tested as unique
    grain_severity: str = "error"
    tests: dict = field(default_factory=dict)  # column -> list of tests
    config: str = ""  # optional {{ config(...) }} body, e.g. "materialized='ephemeral'"


def not_null(*columns):
    return {c: ["not_null"] for c in columns}


def not_null_warn(*columns):
    return {c: [warn("not_null")] for c in columns}


def merge(*dicts):
    out = {}
    for d in dicts:
        for column, tests in d.items():
            out.setdefault(column, []).extend(tests)
    return out


def relationship(to, field_name, severity=None):
    return _with_severity(("relationships", {"to": f"ref('{to}')", "field": field_name}), severity)


def _with_severity(test, severity):
    """Attach a severity to a test, for data that is real enough to be imperfect."""
    if severity is None:
        return test
    name = test if isinstance(test, str) else test[0]
    args = {} if isinstance(test, str) else test[1]
    return (name, args, {"severity": severity})


def warn(test):
    return _with_severity(test, "warn")


def accepted_values(*values):
    return ("accepted_values", {"values": "[" + ", ".join(values) + "]"})


def at_least(minimum, inclusive=True):
    return ("dbt_utils.accepted_range", {"min_value": minimum, "inclusive": str(inclusive).lower()})


def between(low, high):
    return ("dbt_utils.accepted_range", {"min_value": low, "max_value": high, "inclusive": "true"})


def _render_test(test, indent):
    pad = " " * indent
    if isinstance(test, str):
        return [f"{pad}- {test}"]
    name, args = test[0], test[1]
    config = test[2] if len(test) > 2 else {}
    lines = [f"{pad}- {name}:"]
    if args:
        lines += [f"{pad}    arguments:"] + [f"{pad}      {k}: {v}" for k, v in args.items()]
    if config:
        lines += [f"{pad}    config:"] + [f"{pad}      {k}: {v}" for k, v in config.items()]
    return lines


def render_model_sql(model):
    header = f"{{{{ config({model.config}) }}}}\n\n" if model.config else ""
    return header + model.sql.strip("\n") + "\n"


def render_yml(models):
    out = ["version: 2", "", "models:"]
    for m in models:
        out += [f"  - name: {m.name}", f"    description: >", f"      {m.description}"]
        if m.grain:
            cols = "\n".join(f"                - {c}" for c in m.grain)
            out += [
                "    data_tests:",
                "      - dbt_utils.unique_combination_of_columns:",
                "          arguments:",
                "              combination_of_columns:",
                cols,
            ]
            if m.grain_severity != "error":
                out += ["          config:", f"            severity: {m.grain_severity}"]
        if m.tests:
            out.append("    columns:")
            for column, tests in m.tests.items():
                out += [f"      - name: {column}", "        data_tests:"]
                for t in tests:
                    out += _render_test(t, 10)
        out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


def write_group(folder, yml_name, models):
    target = MODELS / folder
    target.mkdir(parents=True, exist_ok=True)
    for m in models:
        (target / f"{m.name}.sql").write_text(render_model_sql(m))
    (target / yml_name).write_text(render_yml(models))
    return len(models)
