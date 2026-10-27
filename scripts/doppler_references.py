#!/usr/bin/env python3
"""Write the references each consumer's Doppler config holds.

    terraform -chdir=doppler output -json references \\
      | DOPPLER_TOKEN="$(doppler configure get token --plain)" \\
        python3 scripts/doppler_references.py [--apply] [--prune]

doppler/ declares the projects and their syncs; this writes what is in
them. Terraform cannot: a doppler_secret resource keeps the value its
reference resolves to in state, and nothing secret goes in state.

Reads {project: {config: {NAME: "${vault.config.SOURCE}"}}} on stdin and,
for each config, sets every NAME whose reference differs from what the
config holds. Doppler refuses a reference to a secret that is itself a
reference, so where the source is one, NAME references its target instead.
Without --apply it only prints what it would do. A reference
to a name the vault does not hold is skipped and reported, never written:
that is an optional setting nobody has set, and the worker treats it as
unset. With --prune, names the config holds but the input does not are
deleted.

Never prints or keeps a secret. It reads raw values, never resolved ones:
in a consumer's config they are the reference strings, and of the vault's
it keeps only those that are references, dropping the rest unread.
Standard library only, so it runs wherever python3 does.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.doppler.com/v3"
REFERENCE = re.compile(r"^\$\{([^.}]+)\.([^.}]+)\.([^.}]+)\}$")
# Doppler also accepts the short forms ${NAME} (same config) and
# ${config.NAME} (same project), which the vault itself uses.
ANY_REFERENCE = re.compile(r"^\$\{([^}]+)\}$")
# Doppler adds these to every config; they are not ours to set or prune.
BUILTIN = {"DOPPLER_PROJECT", "DOPPLER_CONFIG", "DOPPLER_ENVIRONMENT"}


class Doppler:
    def __init__(self, token: str) -> None:
        self._token = token
        self._names: dict[tuple[str, str], set[str]] = {}
        self._references: dict[tuple[str, str], dict[str, str]] = {}

    def _request(self, method: str, path: str, query: dict | None = None, body: dict | None = None) -> dict:
        url = f"{API}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        request = urllib.request.Request(
            url,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={
                "Authorization": f"Bearer {self._token}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Doppler's error body names the problem and carries no values.
            detail = error.read().decode(errors="replace")[:500]
            raise SystemExit(f"{method} {path} {query or ''}: HTTP {error.code}: {detail}") from None

    def names(self, project: str, config: str) -> set[str]:
        key = (project, config)
        if key not in self._names:
            body = self._request("GET", "/configs/config/secrets/names", {"project": project, "config": config})
            self._names[key] = set(body["names"])
        return self._names[key]

    def references_in(self, project: str, config: str) -> dict[str, str]:
        """The names in a config whose value is itself a reference, and the reference.

        Doppler refuses a reference to a secret that is a reference, so one
        to such a secret is pointed at what it references instead. Only the
        reference strings are kept; every other value is dropped unread.
        """
        key = (project, config)
        if key not in self._references:
            found = {}
            for name, raw in self.raw(project, config).items():
                match = ANY_REFERENCE.match(raw)
                if not match:
                    continue
                parts = match.group(1).split(".")
                if len(parts) > 3:
                    continue
                found[name] = "${" + ".".join([project, config][: 3 - len(parts)] + parts) + "}"
            self._references[key] = found
        return self._references[key]

    def raw(self, project: str, config: str) -> dict[str, str]:
        """The config's raw values: the reference strings, not what they resolve to."""
        body = self._request("GET", "/configs/config/secrets", {"project": project, "config": config})
        return {name: secret.get("raw") or "" for name, secret in body["secrets"].items() if name not in BUILTIN}

    def write(self, project: str, config: str, secrets: dict[str, str | None]) -> None:
        # The response echoes every secret, resolved; it is dropped unread.
        self._request("POST", "/configs/config/secrets", body={"project": project, "config": config, "secrets": secrets})


def plan(doppler: Doppler, project: str, config: str, wanted: dict[str, str], prune: bool) -> tuple[dict[str, str | None], list[str]]:
    """What to write to one config, and the references skipped for want of a source."""
    skipped = []
    present = {}
    for name, reference in wanted.items():
        match = REFERENCE.match(reference)
        if not match:
            raise SystemExit(f"{project}/{config} {name}: {reference!r} is not a ${{project.config.NAME}} reference")
        source_project, source_config, source_name = match.groups()
        if source_name not in doppler.names(source_project, source_config):
            skipped.append(f"{name} -> {reference}")
            continue
        # One hop: the vault's dev config holds some values as references
        # to its prd config.
        present[name] = doppler.references_in(source_project, source_config).get(source_name, reference)

    held = doppler.raw(project, config)
    changes: dict[str, str | None] = {name: ref for name, ref in present.items() if held.get(name) != ref}
    if prune:
        changes.update({name: None for name in held if name not in present})
    return changes, skipped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--apply", action="store_true", help="write the changes (default: only print them)")
    parser.add_argument("--prune", action="store_true", help="also delete names the input does not list")
    args = parser.parse_args()

    token = os.environ.get("DOPPLER_TOKEN")
    if not token:
        raise SystemExit("DOPPLER_TOKEN is not set: export it from `doppler configure get token --plain`.")
    references = json.load(sys.stdin)
    doppler = Doppler(token)

    pending = 0
    failed = 0
    for project in sorted(references):
        for config in sorted(references[project]):
            changes, skipped = plan(doppler, project, config, references[project][config], args.prune)
            for line in skipped:
                print(f"  skip   {project}/{config} {line} (not in the vault)")
            for name in sorted(changes):
                verb = "delete" if changes[name] is None else "set"
                print(f"  {verb:<6} {project}/{config} {name}" + ("" if changes[name] is None else f" = {changes[name]}"))
            if changes and args.apply:
                try:
                    doppler.write(project, config, changes)
                except SystemExit as error:
                    print(f"  FAILED {project}/{config}: {error}")
                    failed += 1
                    continue
            pending += len(changes)

    if failed:
        print(f"{failed} config(s) failed; the others were written. Fix and run again.")
        return 1
    if not pending:
        print("No changes.")
    elif args.apply:
        print(f"Wrote {pending} change(s).")
    else:
        print(f"{pending} change(s) to write. Run again with --apply to write them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
