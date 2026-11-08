"""Live contract suite for the apply job's task call (TEST-016, ADR-0012).

scripts/file_sns_confirmations.py makes one outbound call: POST /v1/tasks
on api-kaianolevine-com, after a production apply. It never fails the
apply, so a drift between what it sends and what the API accepts would only
show as a warning in an apply log, and the confirmation task would never be
filed. This suite checks the same call against the deployed development
API instead, on every push to dev and every dev API deploy:

  - the body ``task_request()`` builds satisfies the request schema the API
    publishes for POST /v1/tasks: every required field, no field it does not
    declare, the types, lengths and allowed values it declares;
  - the script's own request, sent by ``post()`` itself, reaches the API
    rather than being blocked at the Cloudflare edge, and an unrecognised
    key is refused with 401 in the API's error envelope.

Read-only. The one post is refused by authentication before the handler,
so nothing is queued and no task is filed. Development has no task queue
anyway, so a real request cannot be checked end to end.

It never points at production: under kaianolevine.com only the hosts in
ALLOWED_DEV_HOSTS are called, the same guard as the other repos' suites.

Configuration:
    CONTRACT_API_URL   the development API's base URL; contract.yml
                       defaults it to https://dev-api.kaianolevine.com

Run by hand with:
    CONTRACT_API_URL=https://dev-api.kaianolevine.com \\
        python3 -m unittest discover -s tests/contract -v

Stdlib only, like the script it checks.
"""

from __future__ import annotations

import json
import os
import re
import sys
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import file_sns_confirmations as fsc  # noqa: E402

PRODUCTION_DOMAIN = "kaianolevine.com"
ALLOWED_DEV_HOSTS = frozenset({"dev-api.kaianolevine.com"})
ENDPOINT = "/v1/tasks"

#: An API key no machine holds. Authentication refuses it before the handler.
UNKNOWN_KEY = "contract-suite-not-a-real-key"

#: A topic shaped like the ones the apply subscribes to.
TOPIC = "arn:aws:sns:us-east-1:123456789012:contract-suite-alerts"


def resolve_api_url() -> str:
    raw = os.environ.get("CONTRACT_API_URL", "").strip()
    if not raw:
        raise RuntimeError(
            "CONTRACT_API_URL is not set — point it at the development API."
        )
    url = urllib.parse.urlsplit(raw)
    host = url.hostname or ""
    local = host in {"localhost", "127.0.0.1"}
    if url.scheme != "https" and not local:
        raise RuntimeError(
            f"CONTRACT_API_URL must be https (or a local API), got {url.scheme}"
        )
    under_production = host == PRODUCTION_DOMAIN or host.endswith(
        f".{PRODUCTION_DOMAIN}"
    )
    if under_production and host not in ALLOWED_DEV_HOSTS:
        raise RuntimeError(
            f"Refusing to run against {host}: only "
            f"{', '.join(sorted(ALLOWED_DEV_HOSTS))} may be called under "
            f"{PRODUCTION_DOMAIN}."
        )
    return f"{url.scheme}://{url.netloc}"


API = resolve_api_url()


def _get_json(path: str) -> Any:
    request = urllib.request.Request(
        API + path,
        headers={"Accept": "application/json", "User-Agent": fsc.USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read())


_JSON_TYPES: dict[str, Any] = {
    "string": str,
    "integer": int,
    "number": (int, float),
    "boolean": bool,
    "array": list,
    "object": dict,
    "null": type(None),
}


def violations(spec: dict[str, Any], schema: dict[str, Any], value: Any, at: str) -> list[str]:
    """Where ``value`` breaks ``schema`` (an OpenAPI 3.1 schema), or []."""
    if "$ref" in schema:
        name = schema["$ref"].rsplit("/", 1)[-1]
        return violations(spec, spec["components"]["schemas"][name], value, at)
    problems: list[str] = []
    for part in schema.get("allOf", []):
        problems += violations(spec, part, value, at)
    for key in ("anyOf", "oneOf"):
        if key in schema:
            options = [violations(spec, s, value, at) for s in schema[key]]
            if all(options):
                problems.append(f"{at}: matches none of {key}: {options}")
    declared = schema.get("type")
    if declared:
        names = declared if isinstance(declared, list) else [declared]
        types = tuple(_JSON_TYPES[n] for n in names if n in _JSON_TYPES)
        if not isinstance(value, types) or (
            isinstance(value, bool) and "boolean" not in names
        ):
            return [*problems, f"{at}: should be {declared}, got {type(value).__name__}"]
    if "const" in schema and value != schema["const"]:
        problems.append(f"{at}: should be {schema['const']!r}, got {value!r}")
    if "enum" in schema and value not in schema["enum"]:
        problems.append(f"{at}: {value!r} is not one of {schema['enum']}")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            problems.append(f"{at}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            problems.append(f"{at}: longer than {schema['maxLength']}")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            problems.append(f"{at}: does not match {schema['pattern']}")
    if isinstance(value, list):
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            problems.append(f"{at}: more than {schema['maxItems']} items")
        for i, item in enumerate(value):
            problems += violations(spec, schema.get("items", {}), item, f"{at}[{i}]")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        for field in schema.get("required", []):
            if field not in value:
                problems.append(f"{at}: missing required {field}")
        for field, item in value.items():
            if field in properties:
                problems += violations(spec, properties[field], item, f"{at}.{field}")
            elif schema.get("additionalProperties") is False:
                problems.append(f"{at}: {field} is not a field the API declares")
    return problems


class TasksContract(unittest.TestCase):
    spec: dict[str, Any]
    operation: dict[str, Any]

    @classmethod
    def setUpClass(cls) -> None:
        cls.spec = _get_json("/openapi.json")
        operation = cls.spec.get("paths", {}).get(ENDPOINT, {}).get("post")
        if operation is None:
            raise AssertionError(f"the API publishes no POST {ENDPOINT}")
        cls.operation = operation

    def test_request_satisfies_the_published_schema(self) -> None:
        schema = self.operation["requestBody"]["content"]["application/json"]["schema"]
        problems = violations(self.spec, schema, fsc.task_request(TOPIC), "body")
        self.assertEqual(problems, [], "the API would refuse the apply job's task")

    def test_unknown_key_is_refused_in_the_error_envelope(self) -> None:
        try:
            status = fsc.post(API, UNKNOWN_KEY, fsc.task_request(TOPIC))
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode(errors="replace")
            try:
                payload = json.loads(raw)
            except ValueError:
                self.fail(
                    f"answered {exc.code} with a non-JSON body — likely blocked "
                    f"at the edge: {raw[:200]}"
                )
            self.assertEqual(exc.code, 401, f"answered {exc.code}: {payload}")
            self.assertIsInstance(payload.get("error", {}).get("code"), str, payload)
            return
        self.fail(f"an unknown key was accepted ({status}): a task may have been queued")


if __name__ == "__main__":
    unittest.main()
