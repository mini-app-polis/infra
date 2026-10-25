#!/usr/bin/env python3
"""Fail when cogs.tf schedules a watcher that watcher-cog does not publish.

    python3 scripts/check_watcher_names.py PATH/TO/watcher_cog/config.py

watcher-cog owns its watcher names: the name= of each WatcherConfig that
get_watchers() in src/watcher_cog/config.py returns. cogs.tf repeats them in
module "watcher"'s schedule_targets, one scheduled invocation per name, and
an invocation whose name watcher-cog does not know fails every tick. CI runs
this against watcher-cog's main.

Reads config.py without importing it (that would need watcher-cog's
dependencies): the names must stay string literals in get_watchers().
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

COGS_TF = Path(__file__).resolve().parents[1] / "cogs.tf"


def published_names(config: Path) -> set[str]:
    """Each WatcherConfig(name="...") inside get_watchers()."""
    tree = ast.parse(config.read_text(), filename=str(config))
    for fn in tree.body:
        if isinstance(fn, ast.FunctionDef) and fn.name == "get_watchers":
            names = {
                kw.value.value
                for call in ast.walk(fn)
                if isinstance(call, ast.Call) and getattr(call.func, "id", None) == "WatcherConfig"
                for kw in call.keywords
                if kw.arg == "name" and isinstance(kw.value, ast.Constant)
            }
            if names:
                return names
    raise SystemExit(
        f'{config}: no WatcherConfig(name="...") found in get_watchers(); '
        f"update {Path(__file__).name} to read it"
    )


def scheduled_names(tf: Path) -> list[str]:
    """The names in module "watcher"'s `for name in [...]` schedule_targets."""
    block = re.search(r'^module "watcher" \{\n(.*?)^\}', tf.read_text(), re.M | re.S)
    targets = block and re.search(
        r"schedule_targets\s*=\s*\{\s*for\s+\w+\s+in\s+\[(.*?)\]", block.group(1), re.S
    )
    if not targets:
        raise SystemExit(
            f'{tf.name}: no `schedule_targets = {{ for name in [...]` in module "watcher"'
        )
    return re.findall(r'"([^"]+)"', targets.group(1))


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_watcher_names.py PATH/TO/watcher_cog/config.py")
    config = Path(sys.argv[1])
    published = published_names(config)
    unknown = [n for n in scheduled_names(COGS_TF) if n not in published]
    for name in unknown:
        print(
            f'error: {COGS_TF.name} schedules watcher "{name}", but watcher-cog\'s '
            f"get_watchers() in {config} publishes only {', '.join(sorted(published))}",
            file=sys.stderr,
        )
    if unknown:
        return 1
    print(f"ok: every watcher {COGS_TF.name} schedules is one watcher-cog publishes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
