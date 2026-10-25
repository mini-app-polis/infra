#!/usr/bin/env python3
"""Fail when outputs.tf's copy of the API's dispatch claim window drifts.

    python3 scripts/check_claim_window.py PATH/TO/dispatch_claims.py

api-kaianolevine-com owns CLAIM_WINDOW, in
src/kaianolevine_api/services/dispatch_claims.py. outputs.tf keeps a copy,
local.dispatch_claim_window_seconds, for the plan-time check that every
cog's longest possible job ends inside it. A copy that has drifted makes
that check prove the wrong thing, so CI runs this against the API's main.

Reads both files without importing anything: CLAIM_WINDOW must stay a
plain dt.timedelta(...) of number literals, and the local a product or sum
of integers.
"""

from __future__ import annotations

import ast
import datetime as dt
import operator
import re
import sys
from pathlib import Path

OUTPUTS_TF = Path(__file__).resolve().parents[1] / "outputs.tf"
LOCAL_NAME = "dispatch_claim_window_seconds"
CONSTANT = "CLAIM_WINDOW"

_OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul}


def api_claim_window_seconds(source: Path) -> int:
    """CLAIM_WINDOW, in seconds, from the module-level assignment."""
    for node in ast.parse(source.read_text(), filename=str(source)).body:
        if (
            isinstance(node, ast.Assign)
            and any(isinstance(t, ast.Name) and t.id == CONSTANT for t in node.targets)
            and isinstance(node.value, ast.Call)
        ):
            func = node.value.func
            name = func.attr if isinstance(func, ast.Attribute) else getattr(func, "id", None)
            if name != "timedelta" or node.value.args:
                break
            kwargs = {kw.arg: ast.literal_eval(kw.value) for kw in node.value.keywords}
            return int(dt.timedelta(**kwargs).total_seconds())
    raise SystemExit(
        f"{source}: no `{CONSTANT} = dt.timedelta(<keyword>=<number>, ...)` found; "
        f"update {Path(__file__).name} to read it"
    )


def _arith(node: ast.expr) -> int:
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in _OPS:
        return _OPS[type(node.op)](_arith(node.left), _arith(node.right))
    raise ValueError(ast.dump(node))


def tf_claim_window_seconds(tf: Path) -> int:
    """local.dispatch_claim_window_seconds, evaluated."""
    match = re.search(rf"^\s*{LOCAL_NAME}\s*=\s*(.+?)\s*(?:#.*)?$", tf.read_text(), re.M)
    if not match:
        raise SystemExit(f"{tf.name}: no `{LOCAL_NAME} = ...` found")
    try:
        return _arith(ast.parse(match.group(1), mode="eval").body)
    except (SyntaxError, ValueError):
        raise SystemExit(
            f"{tf.name}: {LOCAL_NAME} = {match.group(1)} is not integer arithmetic"
        ) from None


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_claim_window.py PATH/TO/dispatch_claims.py")
    source = Path(sys.argv[1])
    api = api_claim_window_seconds(source)
    tf = tf_claim_window_seconds(OUTPUTS_TF)
    if api != tf:
        print(
            f"error: {OUTPUTS_TF.name} local.{LOCAL_NAME} is {tf}s ({tf / 3600:g}h), "
            f"but api-kaianolevine-com's {CONSTANT} is {api}s ({api / 3600:g}h) "
            f"in {source}. Change them together.",
            file=sys.stderr,
        )
        return 1
    print(f"ok: local.{LOCAL_NAME} matches {CONSTANT} ({api}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
