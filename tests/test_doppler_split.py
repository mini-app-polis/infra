"""scripts/doppler_split.py against a fake Doppler: every mode, and no value in any output.

    python3 -m unittest discover tests
"""

from __future__ import annotations

import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import doppler_split as split  # noqa: E402

INVENTORY = """\
doppler_project: mini-app-polis-ecosystem
secrets:
  DEEJAY_COG_API_KEY: {kind: machine-key, tier: 1, configs: [prd, dev]}
  OPENAI_API_KEY:
    kind: manual
    tier: 2
  DB_BACKUP_AWS_SECRET_ACCESS_KEY:
    kind: aws-access-key
    id_var: DB_BACKUP_AWS_ACCESS_KEY_ID
  DB_PASSWORD_KAIANOLEVINE:
    kind: manual
    also: [DB_POLLER_DATABASE_URL_KAIANOLEVINE]
  PUBLIC_SITE_KEY: {kind: not-rotated}
"""

# Values that would be secrets: none may appear in any output.
SECRET_VALUES = ("k-deejay-prd", "k-deejay-dev", "k-old", "sk-openai", "aws-secret", "AKIA1234", "postgres://u:pw@h/db")


def vault() -> dict[str, dict[str, tuple[str, str | None]]]:
    prd = {
        "DEEJAY_COG_API_KEY": "k-deejay-prd",
        "DEEJAY_COG_API_KEY_PREVIOUS": "k-old",
        "OPENAI_API_KEY": "sk-openai",
        "DB_BACKUP_AWS_SECRET_ACCESS_KEY": "aws-secret",
        "DB_BACKUP_AWS_ACCESS_KEY_ID": "AKIA1234",
        "DB_POLLER_DATABASE_URL_KAIANOLEVINE": "postgres://u:pw@h/db",
        "PUBLIC_SITE_KEY": "public",
        "LOGGING_LEVEL": "",
        "SIGNAL_ORGS": "mini-app-polis",
        # prd may reference dev: the dev key, read in prd.
        "PUBLIC_SITE_KEY_DEV": "${mini-app-polis-ecosystem.dev.PUBLIC_SITE_KEY}",
    }
    dev = {
        "DEEJAY_COG_API_KEY": "k-deejay-dev",
        "OPENAI_API_KEY": "${prd.OPENAI_API_KEY}",
        "SIGNAL_ORGS": "${mini-app-polis-ecosystem.prd.SIGNAL_ORGS}",
        "LOGGING_LEVEL": "DEBUG",
        "PUBLIC_SITE_KEY": "public-dev",
    }
    return {"prd": {n: (v, None) for n, v in prd.items()}, "dev": {n: (v, None) for n, v in dev.items()}}


class FakeStore:
    """Projects → configs → name → raw value; resolves references like Doppler."""

    def __init__(self) -> None:
        self.raw: dict[str, dict[str, dict[str, str]]] = {
            split.VAULT: {c: {n: r for n, (r, _) in held.items()} for c, held in vault().items()},
            split.SECRETS: {"prd": {}, "dev": {}},
            split.SETTINGS: {"prd": {}, "dev": {}},
        }
        self.writes: list[tuple[str, str, dict[str, str]]] = []

    def _resolve(self, project: str, config: str, raw: str, depth: int = 0) -> str | None:
        parts = split._reference(raw)
        if parts is None:
            return raw
        if depth > 3:
            return None
        if len(parts) == 1:
            parts = [project, config, *parts]
        elif len(parts) == 2:
            parts = [project, *parts]
        target = self.raw.get(parts[0], {}).get(parts[1], {})
        if parts[2] not in target:
            return None
        return self._resolve(parts[0], parts[1], target[parts[2]], depth + 1)

    def secrets(self, project: str, config: str) -> dict[str, tuple[str, str | None]]:
        held = self.raw.get(project, {}).get(config, {})
        return {n: (r, self._resolve(project, config, r)) for n, r in held.items()}

    def write(self, project: str, config: str, values: dict[str, str]) -> None:
        # Like Doppler: the whole batch is refused when a reference in it does not resolve.
        held = self.raw.setdefault(project, {}).setdefault(config, {})
        before = dict(held)
        held.update(values)
        for name, raw in values.items():
            if self._resolve(project, config, raw) is None:
                held.clear()
                held.update(before)
                raise RuntimeError(f"{name} cannot resolve its reference")
        self.writes.append((project, config, dict(values)))


def run(store: FakeStore, *argv: str, stdin: str = "") -> tuple[int, str]:
    out = io.StringIO()
    code = split.run(list(argv), store, stdin=io.StringIO(stdin), out=out)
    return code, out.getvalue()


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.inventory = self.tmp / "inventory.yaml"
        self.inventory.write_text(INVENTORY)

    def assertNoValues(self, text: str) -> None:
        for value in SECRET_VALUES:
            self.assertNotIn(value, text)


class SortTest(Base):
    def test_rotated_entries_their_rewrites_and_previous_slots_are_secrets(self) -> None:
        inventory = split.load_inventory(self.inventory)
        home = split.sort_names(split.vault_names(FakeStore()), split.secret_names(inventory))
        secrets = {n for n, p in home.items() if p == split.SECRETS}
        self.assertEqual(
            secrets,
            {
                "DEEJAY_COG_API_KEY",
                "DEEJAY_COG_API_KEY_PREVIOUS",
                "OPENAI_API_KEY",
                "DB_BACKUP_AWS_SECRET_ACCESS_KEY",
                "DB_BACKUP_AWS_ACCESS_KEY_ID",
                "DB_POLLER_DATABASE_URL_KAIANOLEVINE",
            },
        )
        # not-rotated, and names the inventory does not list, are settings.
        self.assertEqual(home["PUBLIC_SITE_KEY"], split.SETTINGS)
        self.assertEqual(home["LOGGING_LEVEL"], split.SETTINGS)
        self.assertEqual(home["SIGNAL_ORGS"], split.SETTINGS)

    def test_sort_prints_names_only(self) -> None:
        code, out = run(FakeStore(), "sort", str(self.inventory))
        self.assertEqual(code, 0)
        self.assertIn("secret  DEEJAY_COG_API_KEY", out)
        self.assertIn("setting SIGNAL_ORGS", out)
        self.assertIn("6 secret(s), 4 setting(s).", out)
        self.assertNoValues(out)


class GenerateTest(Base):
    def generate(self, *extra: str) -> tuple[int, str]:
        # No store: generate must not need Doppler or a token.
        out = io.StringIO()
        code = split.run(["generate", str(self.inventory), "--out", str(self.tmp / "names.tf.json"), *extra], out=out)
        return code, out.getvalue()

    def test_writes_the_same_secret_names_sort_uses(self) -> None:
        code, _ = self.generate()
        self.assertEqual(code, 0)
        body = json.loads((self.tmp / "names.tf.json").read_text())
        names = body["locals"]["vault_secret_names"]
        self.assertEqual(names, sorted(split.secret_names(split.load_inventory(self.inventory))))

    def test_check_passes_when_current_and_fails_when_the_inventory_moves_on(self) -> None:
        code, out = self.generate("--check")
        self.assertEqual(code, 1, out)
        self.assertEqual(self.generate()[0], 0)
        self.assertEqual(self.generate("--check")[0], 0)
        self.inventory.write_text(INVENTORY + "  NEW_API_KEY: {kind: manual}\n")
        code, out = self.generate("--check")
        self.assertEqual(code, 1)
        self.assertIn("out of date", out)

    def test_the_committed_file_is_a_sorted_list_of_names(self) -> None:
        body = json.loads(split.GENERATED.read_text())
        names = body["locals"]["vault_secret_names"]
        self.assertTrue(names)
        self.assertEqual(names, sorted(set(names)))
        self.assertEqual(split.GENERATED.read_text(), split.generated(frozenset(names)))


class CopyTest(Base):
    def test_a_dry_run_writes_nothing_and_names_each_copy(self) -> None:
        store = FakeStore()
        code, out = run(store, "copy", str(self.inventory))
        self.assertEqual(code, 0)
        self.assertEqual(store.writes, [])
        self.assertIn(f"copy   {split.SECRETS}/prd DEEJAY_COG_API_KEY", out)
        self.assertIn(f"copy   {split.SETTINGS}/dev SIGNAL_ORGS", out)
        self.assertIn("Run again with --apply", out)
        self.assertNoValues(out)

    def test_apply_copies_each_value_home_and_rehomes_vault_references(self) -> None:
        store = FakeStore()
        code, out = run(store, "copy", str(self.inventory), "--apply")
        self.assertEqual(code, 0)
        self.assertNoValues(out)
        secrets, settings = store.raw[split.SECRETS], store.raw[split.SETTINGS]
        self.assertEqual(secrets["prd"]["DEEJAY_COG_API_KEY"], "k-deejay-prd")
        self.assertEqual(secrets["dev"]["DEEJAY_COG_API_KEY"], "k-deejay-dev")
        self.assertEqual(secrets["dev"]["OPENAI_API_KEY"], "${mini-app-polis-secrets.prd.OPENAI_API_KEY}")
        self.assertEqual(settings["dev"]["SIGNAL_ORGS"], "${mini-app-polis-settings.prd.SIGNAL_ORGS}")
        self.assertEqual(settings["prd"]["LOGGING_LEVEL"], "")
        self.assertNotIn("SIGNAL_ORGS", secrets["prd"])
        self.assertNotIn("OPENAI_API_KEY", settings["prd"])
        # A prd value referencing dev is copied as a reference into dev's new home.
        self.assertEqual(settings["prd"]["PUBLIC_SITE_KEY_DEV"], "${mini-app-polis-settings.dev.PUBLIC_SITE_KEY}")
        # Plain values everywhere first, then references, so every target exists first.
        written = [(p, c, any(split._reference(v) for v in values.values())) for p, c, values in store.writes]
        self.assertEqual([r for _, _, r in written], sorted(r for _, _, r in written))
        # Every copied value resolves to what the vault's resolves to.
        for config in split.VAULT_CONFIGS:
            for name, (_, computed) in store.secrets(split.VAULT, config).items():
                home = split.SECRETS if name in secrets[config] else split.SETTINGS
                self.assertEqual(store.secrets(home, config)[name][1], computed, f"{config} {name}")

    def test_a_second_run_copies_nothing(self) -> None:
        store = FakeStore()
        run(store, "copy", str(self.inventory), "--apply")
        store.writes.clear()
        code, out = run(store, "copy", str(self.inventory), "--apply")
        self.assertEqual(code, 0)
        self.assertEqual(store.writes, [])
        self.assertIn("No changes.", out)

    def test_a_reference_outside_the_vault_is_copied_as_it_is(self) -> None:
        self.assertEqual(split.rehome("${spotify.prd.SPOTIPY_REFRESH_TOKEN}", "prd", {}), "${spotify.prd.SPOTIPY_REFRESH_TOKEN}")
        self.assertEqual(split.rehome("plain", "prd", {"plain": split.SECRETS}), "plain")


class SnapshotVerifyTest(Base):
    REFERENCES = {"deejay-cog": {"prd": {}, "dev": {}}}

    def consumer(self, store: FakeStore, project: str) -> None:
        for config in ("prd", "dev"):
            store.raw["deejay-cog"] = store.raw.get("deejay-cog", {})
            store.raw["deejay-cog"][config] = {
                "DEEJAY_COG_API_KEY": "${" + f"{project}.{config}.DEEJAY_COG_API_KEY" + "}",
                "LOGGING_LEVEL": "${" + f"{split.VAULT if project == split.VAULT else split.SETTINGS}.{config}.LOGGING_LEVEL" + "}",
                "OWN_SETTING": "x",
            }

    def take(self, store: FakeStore) -> Path:
        path = self.tmp / "snapshot.json"
        code, out = run(store, "snapshot", "--out", str(path), stdin=json.dumps(self.REFERENCES))
        self.assertEqual(code, 0)
        self.assertNoValues(out)
        return path

    def test_the_snapshot_holds_hashes_only(self) -> None:
        store = FakeStore()
        self.consumer(store, split.VAULT)
        path = self.take(store)
        text = path.read_text()
        self.assertNoValues(text)
        taken = json.loads(text)
        self.assertEqual(
            taken["deejay-cog"]["prd"]["DEEJAY_COG_API_KEY"],
            hashlib.sha256(b"k-deejay-prd").hexdigest(),
        )

    def test_verify_passes_once_consumers_point_at_the_new_projects(self) -> None:
        store = FakeStore()
        self.consumer(store, split.VAULT)
        path = self.take(store)
        run(store, "copy", str(self.inventory), "--apply")
        self.consumer(store, split.SECRETS)
        code, out = run(store, "verify", "--snapshot", str(path), stdin=json.dumps(self.REFERENCES))
        self.assertEqual(code, 0, out)
        self.assertIn("All 2 config(s)", out)
        self.assertNoValues(out)

    def test_verify_fails_on_a_reference_still_into_the_vault(self) -> None:
        store = FakeStore()
        self.consumer(store, split.VAULT)
        path = self.take(store)
        code, out = run(store, "verify", "--snapshot", str(path), stdin=json.dumps(self.REFERENCES))
        self.assertEqual(code, 1)
        self.assertIn(f"FAILED deejay-cog/prd DEEJAY_COG_API_KEY: still references {split.VAULT}", out)
        self.assertNoValues(out)

    def test_verify_fails_on_a_changed_value_and_one_that_does_not_resolve(self) -> None:
        store = FakeStore()
        self.consumer(store, split.VAULT)
        path = self.take(store)
        run(store, "copy", str(self.inventory), "--apply")
        self.consumer(store, split.SECRETS)
        store.raw[split.SECRETS]["prd"]["DEEJAY_COG_API_KEY"] = "k-different"
        del store.raw[split.SETTINGS]["dev"]["LOGGING_LEVEL"]
        code, out = run(store, "verify", "--snapshot", str(path), stdin=json.dumps(self.REFERENCES))
        self.assertEqual(code, 1)
        self.assertIn("FAILED deejay-cog/prd DEEJAY_COG_API_KEY: resolves to a different value", out)
        self.assertIn("FAILED deejay-cog/dev LOGGING_LEVEL: does not resolve", out)
        self.assertNotIn("k-different", out)
        self.assertNoValues(out)

    def test_another_project_is_a_failure_unless_allowed(self) -> None:
        store = FakeStore()
        store.raw["spotify"] = {"prd": {"SPOTIPY_REFRESH_TOKEN": "tok"}}
        store.raw["deejay-cog"] = {"prd": {"SPOTIPY_REFRESH_TOKEN": "${spotify.prd.SPOTIPY_REFRESH_TOKEN}"}}
        refs = {"deejay-cog": {"prd": {}}}
        path = self.tmp / "snapshot.json"
        run(store, "snapshot", "--out", str(path), stdin=json.dumps(refs))
        code, out = run(store, "verify", "--snapshot", str(path), stdin=json.dumps(refs))
        self.assertEqual(code, 1)
        self.assertIn("references spotify", out)
        code, out = run(store, "verify", "--snapshot", str(path), "--allow", "spotify", stdin=json.dumps(refs))
        self.assertEqual(code, 0, out)
        self.assertNotIn("tok", out.replace("token", ""))

    def test_a_config_missing_from_the_snapshot_fails(self) -> None:
        store = FakeStore()
        self.consumer(store, split.SECRETS)
        path = self.tmp / "snapshot.json"
        path.write_text("{}")
        code, out = run(store, "verify", "--snapshot", str(path), stdin=json.dumps(self.REFERENCES))
        self.assertEqual(code, 1)
        self.assertIn("deejay-cog/prd: not in the snapshot", out)


if __name__ == "__main__":
    unittest.main()
