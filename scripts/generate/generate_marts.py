#!/usr/bin/env python3
"""Generates the intermediate and mart layers, and the tests that sit beside them.

Each dataset has its own module (models_tpcds.py, ...) holding the models as data:
the SQL, a description, the columns forming the grain, and the tests per column.
This script runs them all. The output is committed; rerunning it must leave the
working tree unchanged.

Usage: python3 scripts/generate/generate_marts.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import models_tpcds  # noqa: E402
import models_wanderbricks  # noqa: E402
import models_tpch  # noqa: E402
import models_clickbench  # noqa: E402

MODULES = {"tpcds": models_tpcds, "wanderbricks": models_wanderbricks, "tpch": models_tpch, "clickbench": models_clickbench}

if __name__ == "__main__":
    counts = {name: module.generate() for name, module in MODULES.items()}
    print("models written:", counts, "total", sum(counts.values()))
