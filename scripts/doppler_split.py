#!/usr/bin/env python3
"""Split the vault into a secrets project and a settings project, and prove the move.

    python3 scripts/doppler_split.py generate PATH/TO/secrets/inventory.yaml [--check]
    python3 scripts/doppler_split.py sort PATH/TO/secrets/inventory.yaml
    python3 scripts/doppler_split.py copy PATH/TO/secrets/inventory.yaml [--apply]
    terraform -chdir=doppler output -json references \\
      | python3 scripts/doppler_split.py snapshot --out FILE
    terraform -chdir=doppler output -json references \\
      | python3 scripts/doppler_split.py verify --snapshot FILE [--allow PROJECT ...]

DOPPLER_TOKEN must be set (`doppler configure get token --plain`), except
for ``generate``.

mini-app-polis-ecosystem (prd and dev) is the single vault the values are
copied from. They move to two projects: mini-app-polis-secrets holds what
rotator-cog rotates, mini-app-polis-settings everything else. doppler/
points every reference at one of the two, by the names ``generate`` writes.

- ``generate`` writes the secret names to doppler/vault_secret_names.tf.json,
  the local ``vault_secret_names`` that doppler/ sorts every reference by:
  a name in it is referenced in mini-app-polis-secrets, any other in
  mini-app-polis-settings. A secret is every entry of rotator-cog's
  ``secrets/inventory.yaml`` whose kind is rotated (machine-key,
  aws-access-key, generated, provider-api, manual), with the names its
  rotation also writes: its ``id_var``, its ``also`` names, and the
  ``_PREVIOUS`` slot of each. ``--check`` writes nothing and exits non-zero
  when the file differs from what the inventory gives. Needs no token.
- ``sort`` puts each vault name in one of the two by the same rule. Every
  vault name that is not a secret is a setting.
- ``copy`` copies each vault value into its new project, in the same config.
  A value that is a reference into the vault (the vault's dev holds some as
  references to its prd) is copied as a reference to the name's new home.
  Dry run by default; ``--apply`` writes. A value the new project already
  holds unchanged is skipped, so it can be run again.
- ``snapshot`` writes, for every consumer project and config named on stdin,
  the SHA-256 of each resolved value to a local file.
- ``verify`` checks, for every consumer project and config named on stdin,
  that every reference points at mini-app-polis-secrets or
  mini-app-polis-settings (or a project passed with ``--allow``) and none at
  the vault, that every reference resolves, and that each resolved value's
  hash equals the snapshot's. It exits non-zero on any failure, naming each
  failing name and config.

Names only, never values: no mode prints, logs or writes a secret value,
and the snapshot holds hashes. stdin is ``doppler/``'s ``references``
output, the same input scripts/doppler_references.py reads; only its project
and config keys are used. The inventory is read with PyYAML.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any, Protocol

VAULT = "mini-app-polis-ecosystem"
SECRETS = "mini-app-polis-secrets"
SETTINGS = "mini-app-polis-settings"
VAULT_CONFIGS = ("prd", "dev")
ROTATED_KINDS = frozenset({"machine-key", "aws-access-key", "generated", "provider-api", "manual"})
# Doppler adds these to every config; they are not ours to copy or check.
BUILTIN = frozenset({"DOPPLER_PROJECT", "DOPPLER_CONFIG", "DOPPLER_ENVIRONMENT"})
# The secret names as doppler/ reads them, written by ``generate``.
GENERATED = Path(__file__).resolve().parents[1] / "doppler" / "vault_secret_names.tf.json"


class Store(Protocol):
    """What the modes need from Doppler. :class:`DopplerApi` is the real one."""

    def secrets(self, project: str, config: str) -> dict[str, tuple[str, str | None]]:
        """Each name's raw value and what it resolves to (None when it does not)."""
        ...

    def write(self, project: str, config: str, values: dict[str, str]) -> None:
        """Set each name to its (raw) value."""
        ...


# ── sort ─────────────────────────────────────────────────────────────────


def load_inventory(path: Path) -> dict[str, Any]:
    try:
        import yaml
    except ImportError:
        raise SystemExit("sort and copy read the inventory with PyYAML: pip install pyyaml") from None
    data = yaml.safe_load(path.read_text())
    if not isinstance(data, dict) or not isinstance(data.get("secrets"), dict):
        raise SystemExit(f"{path}: no `secrets:` mapping")
    return data


def secret_names(inventory: Mapping[str, Any]) -> frozenset[str]:
    """Every name a rotation writes: the rotated entries, what each also
    rewrites, and the _PREVIOUS slot of each."""
    names: set[str] = set()
    for name, entry in inventory["secrets"].items():
        if not isinstance(entry, dict) or entry.get("kind") not in ROTATED_KINDS:
            continue
        names.add(name)
        if entry.get("id_var"):
            names.add(str(entry["id_var"]))
        names.update(str(n) for n in entry.get("also") or [])
    return frozenset(names | {f"{n}_PREVIOUS" for n in names})


def sort_names(vault_names: Iterable[str], secrets: frozenset[str]) -> dict[str, str]:
    """Each vault name and the project it moves to."""
    return {name: SECRETS if name in secrets else SETTINGS for name in vault_names}


def generated(secrets: frozenset[str]) -> str:
    """doppler/vault_secret_names.tf.json's content for these secret names."""
    body = {
        "//": "Written by scripts/doppler_split.py generate from rotator-cog's secrets/inventory.yaml; do not edit.",
        "locals": {"vault_secret_names": sorted(secrets)},
    }
    return json.dumps(body, indent=2) + "\n"


def vault_names(store: Store) -> set[str]:
    return {name for config in VAULT_CONFIGS for name in store.secrets(VAULT, config) if name not in BUILTIN}


# ── copy ─────────────────────────────────────────────────────────────────


def _reference(raw: str) -> list[str] | None:
    """The parts of a ``${...}`` reference, or None when the value is not one."""
    if raw.startswith("${") and raw.endswith("}") and raw.count("${") == 1:
        parts = raw[2:-1].split(".")
        if 1 <= len(parts) <= 3 and all(parts):
            return parts
    return None


def rehome(raw: str, config: str, home: Mapping[str, str]) -> str:
    """A vault value as it is copied: a reference into the vault points at
    the name's new project; anything else is copied as it is."""
    parts = _reference(raw)
    if parts is None:
        return raw
    if len(parts) == 3 and parts[0] != VAULT:
        return raw  # into another project, which is not moving
    name = parts[-1]
    source_config = parts[-2] if len(parts) >= 2 else config
    if name not in home:
        return raw
    return "${" + f"{home[name]}.{source_config}.{name}" + "}"


def plan_copy(store: Store, home: Mapping[str, str]) -> list[tuple[str, str, dict[str, str]]]:
    """(project, config, values to write), prd before dev and secrets before
    settings. :func:`write_batches` decides the order they are written in."""
    plans: list[tuple[str, str, dict[str, str]]] = []
    for config in VAULT_CONFIGS:
        source = store.secrets(VAULT, config)
        for project in (SECRETS, SETTINGS):
            held = store.secrets(project, config)
            values = {
                name: rehome(raw, config, home)
                for name, (raw, _) in source.items()
                if name not in BUILTIN and home.get(name) == project
            }
            changed = {name: value for name, value in values.items() if held.get(name, (None, None))[0] != value}
            plans.append((project, config, changed))
    return plans


def write_batches(plans: Iterable[tuple[str, str, dict[str, str]]]) -> list[tuple[str, str, dict[str, str]]]:
    """The plans as Doppler can take them: every plain value first, then every
    reference. Doppler refuses a reference that does not resolve, and a value
    in prd may reference dev as well as the other way round, so no order of
    configs alone writes every target before what references it."""
    plans = list(plans)
    batches: list[tuple[str, str, dict[str, str]]] = []
    for references in (False, True):
        for project, config, values in plans:
            part = {n: v for n, v in values.items() if (_reference(v) is not None) == references}
            if part:
                batches.append((project, config, part))
    return batches


# ── snapshot and verify ──────────────────────────────────────────────────


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def consumers(references: Mapping[str, Mapping[str, Any]]) -> list[tuple[str, str]]:
    return [(project, config) for project in sorted(references) for config in sorted(references[project])]


def snapshot(store: Store, targets: Iterable[tuple[str, str]]) -> dict[str, dict[str, dict[str, str | None]]]:
    """Each consumer config's names and the hash of what each resolves to."""
    out: dict[str, dict[str, dict[str, str | None]]] = {}
    for project, config in targets:
        resolved = store.secrets(project, config)
        out.setdefault(project, {})[config] = {
            name: None if computed is None else digest(computed)
            for name, (_, computed) in sorted(resolved.items())
            if name not in BUILTIN
        }
    return out


def verify(
    store: Store,
    targets: Iterable[tuple[str, str]],
    taken: Mapping[str, Mapping[str, Mapping[str, str | None]]],
    allowed: Iterable[str] = (),
) -> list[str]:
    """Every failure, one line each, naming the config and the name."""
    homes = {SECRETS, SETTINGS, *allowed}
    failures: list[str] = []
    for project, config in targets:
        before = taken.get(project, {}).get(config)
        if before is None:
            failures.append(f"{project}/{config}: not in the snapshot")
            continue
        now = {name: held for name, held in store.secrets(project, config).items() if name not in BUILTIN}
        for name in sorted(set(before) | set(now)):
            where = f"{project}/{config} {name}"
            if name not in now:
                failures.append(f"{where}: gone since the snapshot")
                continue
            raw, computed = now[name]
            parts = _reference(raw)
            if parts is not None:
                target = parts[0] if len(parts) == 3 else project
                if target == VAULT:
                    failures.append(f"{where}: still references {VAULT}")
                elif target not in homes:
                    failures.append(f"{where}: references {target}, not {SECRETS} or {SETTINGS}")
            if computed is None:
                failures.append(f"{where}: does not resolve")
                continue
            if name not in before:
                failures.append(f"{where}: not in the snapshot")
            elif before[name] != digest(computed):
                failures.append(f"{where}: resolves to a different value than at the snapshot")
    return failures


# ── Doppler ──────────────────────────────────────────────────────────────


class DopplerApi:
    """The Store over Doppler's API, through doppler_references.Doppler's requests."""

    def __init__(self, token: str) -> None:
        from doppler_references import Doppler

        self._doppler = Doppler(token)

    def secrets(self, project: str, config: str) -> dict[str, tuple[str, str | None]]:
        body = self._doppler._request("GET", "/configs/config/secrets", {"project": project, "config": config})
        return {
            name: (secret.get("raw") or "", secret.get("computed"))
            for name, secret in body["secrets"].items()
        }

    def write(self, project: str, config: str, values: dict[str, str]) -> None:
        # The response echoes every secret, resolved; write drops it unread.
        self._doppler.write(project, config, dict(values))


# ── main ─────────────────────────────────────────────────────────────────


def _store() -> Store:
    token = os.environ.get("DOPPLER_TOKEN")
    if not token:
        raise SystemExit("DOPPLER_TOKEN is not set: export it from `doppler configure get token --plain`.")
    return DopplerApi(token)


def run(argv: list[str], store: Store | None = None, stdin: Any = sys.stdin, out: Any = sys.stdout) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    modes = parser.add_subparsers(dest="mode", required=True)
    for mode in ("generate", "sort", "copy"):
        sub = modes.add_parser(mode)
        sub.add_argument("inventory", type=Path, help="rotator-cog's secrets/inventory.yaml")
        if mode == "generate":
            sub.add_argument("--out", type=Path, default=GENERATED, help="where to write (default: %(default)s)")
            sub.add_argument("--check", action="store_true", help="write nothing; fail when the file is out of date")
        if mode == "copy":
            sub.add_argument("--apply", action="store_true", help="write (default: only print)")
    taking = modes.add_parser("snapshot")
    taking.add_argument("--out", type=Path, required=True, help="where to write the hashes")
    checking = modes.add_parser("verify")
    checking.add_argument("--snapshot", type=Path, required=True, help="the file snapshot wrote")
    checking.add_argument(
        "--allow", action="append", default=[], metavar="PROJECT",
        help="another project a consumer may reference (spotify)",
    )
    args = parser.parse_args(argv)

    def say(line: str) -> None:
        print(line, file=out)

    if args.mode == "generate":
        names = secret_names(load_inventory(args.inventory))
        content = generated(names)
        current = args.out.read_text() if args.out.exists() else None
        if args.check:
            if current != content:
                say(f"{args.out} is out of date with {args.inventory}: run generate and commit the result.")
                return 1
            say(f"{args.out} matches {args.inventory}: {len(names)} secret name(s).")
            return 0
        if current == content:
            say(f"{args.out} is up to date: {len(names)} secret name(s).")
        else:
            args.out.write_text(content)
            say(f"Wrote {len(names)} secret name(s) to {args.out}.")
        return 0

    store = store or _store()

    if args.mode in ("sort", "copy"):
        home = sort_names(vault_names(store), secret_names(load_inventory(args.inventory)))
        if args.mode == "sort":
            for name in sorted(home):
                say(f"{'secret' if home[name] == SECRETS else 'setting':<7} {name}")
            secrets = sum(1 for p in home.values() if p == SECRETS)
            say(f"{secrets} secret(s), {len(home) - secrets} setting(s).")
            return 0
        plans = plan_copy(store, home)
        pending = 0
        for project, config, values in plans:
            for name in sorted(values):
                say(f"  copy   {project}/{config} {name}")
            pending += len(values)
        if args.apply:
            for project, config, values in write_batches(plans):
                store.write(project, config, values)
        if not pending:
            say("No changes.")
        elif args.apply:
            say(f"Copied {pending} value(s).")
        else:
            say(f"{pending} value(s) to copy. Run again with --apply to copy them.")
        return 0

    targets = consumers(json.load(stdin))
    if args.mode == "snapshot":
        taken = snapshot(store, targets)
        args.out.write_text(json.dumps(taken, indent=2, sort_keys=True) + "\n")
        count = sum(len(names) for configs in taken.values() for names in configs.values())
        say(f"Wrote the hashes of {count} name(s) in {len(targets)} config(s) to {args.out}.")
        return 0

    failures = verify(store, targets, json.loads(args.snapshot.read_text()), args.allow)
    for line in failures:
        say(f"  FAILED {line}")
    if failures:
        say(f"{len(failures)} failure(s) in {len(targets)} config(s).")
        return 1
    say(f"All {len(targets)} config(s) reference only {SECRETS} and {SETTINGS} and match the snapshot.")
    return 0


def main() -> int:
    return run(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
