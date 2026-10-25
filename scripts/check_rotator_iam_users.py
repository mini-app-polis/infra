#!/usr/bin/env python3
"""Fail when cogs.tf grants the rotator a different set of IAM users than it rotates.

    python3 scripts/check_rotator_iam_users.py PATH/TO/secrets/inventory.yaml

rotator-cog owns which IAM users' access keys it rotates: the iam_user of
each aws-access-key entry in its secrets/inventory.yaml. cogs.tf repeats
them in local.rotator_iam_users, the users its role may mint and delete
keys for. A user missing here fails its rotation; one here the inventory
does not name is a grant nothing uses. CI runs this against rotator-cog's
main.

Reads the inventory without a YAML parser (stdlib only): each iam_user must
stay a plain `iam_user: <name>` line.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

COGS_TF = Path(__file__).resolve().parents[1] / "cogs.tf"
LOCAL_NAME = "rotator_iam_users"


def rotated_users(inventory: Path) -> set[str]:
    """Every `iam_user:` value in the inventory."""
    names = {
        name.strip("'\"")
        for name in re.findall(r"^\s+iam_user:\s*(\S+)", inventory.read_text(), re.M)
    }
    if not names:
        raise SystemExit(
            f"{inventory}: no `iam_user: <name>` found; update {Path(__file__).name} to read it"
        )
    return names


def granted_users(tf: Path) -> set[str]:
    """The keys of local.rotator_iam_users."""
    block = re.search(rf"^(\s*){LOCAL_NAME}\s*=\s*\{{\n(.*?)^\1\}}", tf.read_text(), re.M | re.S)
    if not block:
        raise SystemExit(f"{tf.name}: no `{LOCAL_NAME} = {{ ... }}` found")
    return set(re.findall(r'^\s*"([^"]+)"\s*=', block.group(2), re.M))


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check_rotator_iam_users.py PATH/TO/secrets/inventory.yaml")
    inventory = Path(sys.argv[1])
    rotated = rotated_users(inventory)
    granted = granted_users(COGS_TF)
    for name in sorted(rotated - granted):
        print(
            f'error: {inventory} rotates IAM user "{name}", but {COGS_TF.name} '
            f"local.{LOCAL_NAME} does not grant the rotator its access keys",
            file=sys.stderr,
        )
    for name in sorted(granted - rotated):
        print(
            f'error: {COGS_TF.name} local.{LOCAL_NAME} grants the rotator IAM user "{name}", '
            f"but {inventory} names no aws-access-key entry for it",
            file=sys.stderr,
        )
    if rotated != granted:
        return 1
    print(f"ok: local.{LOCAL_NAME} grants exactly the IAM users the inventory rotates")
    return 0


if __name__ == "__main__":
    sys.exit(main())
