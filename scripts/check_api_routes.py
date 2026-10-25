#!/usr/bin/env python3
"""Fail when observability.tf draws a route its API does not publish.

    python3 scripts/check_api_routes.py PATH/TO/main.py [PATH/TO/main.py ...]

Each API owns the routes it gives their own Latency series: METRICS_ROUTES
in its main.py, passed as routes= to RequestMetricsMiddleware, whose
service= names the Service dimension it publishes under. observability.tf
repeats them in local.dashboard_api_routes, keyed by that service, and a
route listed there that the API does not publish draws an empty line. CI
runs this against each API's main.

Reads main.py without importing it (that would need the API's
dependencies): METRICS_ROUTES must stay a module-level tuple or list of
string literals, and service= a string literal.
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

OBSERVABILITY_TF = Path(__file__).resolve().parents[1] / "observability.tf"
LOCAL_NAME = "dashboard_api_routes"
CONSTANT = "METRICS_ROUTES"
MIDDLEWARE = "RequestMetricsMiddleware"


def published_routes(main: Path) -> tuple[str, set[str]]:
    """(service=, METRICS_ROUTES) from the API's main.py."""
    tree = ast.parse(main.read_text(), filename=str(main))
    routes = next(
        (
            ast.literal_eval(node.value)
            for node in tree.body
            if isinstance(node, ast.Assign)
            and any(isinstance(t, ast.Name) and t.id == CONSTANT for t in node.targets)
        ),
        None,
    )
    service = next(
        (
            kw.value.value
            for call in ast.walk(tree)
            if isinstance(call, ast.Call)
            and any(isinstance(a, ast.Name) and a.id == MIDDLEWARE for a in call.args)
            for kw in call.keywords
            if kw.arg == "service" and isinstance(kw.value, ast.Constant)
        ),
        None,
    )
    if not isinstance(routes, (tuple, list)) or not all(isinstance(r, str) for r in routes):
        raise SystemExit(
            f'{main}: no module-level `{CONSTANT} = ("...", ...)` found; '
            f"update {Path(__file__).name} to read it"
        )
    if not isinstance(service, str):
        raise SystemExit(
            f'{main}: no add_middleware({MIDDLEWARE}, service="...") found; '
            f"update {Path(__file__).name} to read it"
        )
    return service, set(routes)


def drawn_routes(tf: Path) -> dict[str, list[str]]:
    """local.dashboard_api_routes, as {service: [route, ...]}."""
    block = re.search(rf"^(\s*){LOCAL_NAME}\s*=\s*\{{\n(.*?)^\1\}}", tf.read_text(), re.M | re.S)
    if not block:
        raise SystemExit(f"{tf.name}: no `{LOCAL_NAME} = {{ ... }}` found")
    return {
        service: re.findall(r'"([^"]+)"', routes)
        for service, routes in re.findall(r'"([^"]+)"\s*=\s*\[(.*?)\]', block.group(2), re.S)
    }


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit("usage: check_api_routes.py PATH/TO/main.py [PATH/TO/main.py ...]")
    published = dict(published_routes(Path(p)) for p in sys.argv[1:])
    sources = dict(zip(published, sys.argv[1:]))
    errors = 0
    for service, routes in drawn_routes(OBSERVABILITY_TF).items():
        if service not in published:
            print(
                f'error: {OBSERVABILITY_TF.name} local.{LOCAL_NAME} lists routes for "{service}", '
                f"but no main.py given publishes under that service "
                f"(given: {', '.join(sorted(published))})",
                file=sys.stderr,
            )
            errors += 1
            continue
        for route in routes:
            if route not in published[service]:
                print(
                    f'error: {OBSERVABILITY_TF.name} local.{LOCAL_NAME} draws "{route}" for '
                    f"{service}, but its {CONSTANT} in {sources[service]} publishes only "
                    f"{', '.join(sorted(published[service]))}",
                    file=sys.stderr,
                )
                errors += 1
    if errors:
        return 1
    print(f"ok: every route local.{LOCAL_NAME} draws is one its API publishes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
