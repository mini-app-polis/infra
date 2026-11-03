"""scripts/file_sns_confirmations.py without the network.

    python3 -m unittest discover tests
"""

from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import file_sns_confirmations as fsc  # noqa: E402

ADDRESS = "module.evaluator.aws_sns_topic_subscription.alerts_email"
TOPIC = "arn:aws:sns:us-east-1:123456789012:evaluator-alerts"


def plan(actions: list[str], protocol: str = "email") -> dict:
    return {
        "resource_changes": [
            {
                "address": ADDRESS,
                "type": "aws_sns_topic_subscription",
                "change": {"actions": actions, "after": {"protocol": protocol}},
            },
            {"address": "aws_sns_topic.x", "type": "aws_sns_topic", "change": {"actions": ["create"], "after": {}}},
        ]
    }


STATE = {
    "values": {
        "root_module": {
            "resources": [],
            "child_modules": [
                {
                    "resources": [
                        {
                            "address": ADDRESS,
                            "values": {"topic_arn": TOPIC, "endpoint": "secret@example.com"},
                        }
                    ]
                }
            ],
        }
    }
}

ENV = {"INFRA_APPLY_API_URL": "https://api.example.com/", "INFRA_APPLY_API_KEY": "k-not-printed"}


def run(plan_doc: dict, env: dict) -> tuple[int, str]:
    with tempfile.TemporaryDirectory() as tmp:
        plan_path = Path(tmp, "plan.json")
        state_path = Path(tmp, "state.json")
        plan_path.write_text(json.dumps(plan_doc))
        state_path.write_text(json.dumps(STATE))
        out = io.StringIO()
        with mock.patch.dict(os.environ, env, clear=True), redirect_stdout(out):
            code = fsc.main(["x", str(plan_path), str(state_path)])
    return code, out.getvalue()


class CreatedSubscriptions(unittest.TestCase):
    def test_only_created_email_subscriptions(self) -> None:
        self.assertEqual(fsc.created_subscriptions(plan(["create"])), [ADDRESS])
        self.assertEqual(fsc.created_subscriptions(plan(["update"])), [])
        self.assertEqual(fsc.created_subscriptions(plan(["create"], protocol="lambda")), [])

    def test_replacement_counts_as_created(self) -> None:
        self.assertEqual(fsc.created_subscriptions(plan(["delete", "create"])), [ADDRESS])


class TaskRequest(unittest.TestCase):
    def test_shape_and_stable_external_id(self) -> None:
        body = fsc.task_request(TOPIC)
        self.assertEqual(body["source"], "infra-apply")
        self.assertTrue(body["external_id"].startswith("infra-apply."))
        self.assertEqual(body["external_id"], fsc.task_request(TOPIC)["external_id"])
        self.assertEqual(body["draft"]["labels"], ["person"])
        self.assertIn("evaluator-alerts", body["draft"]["title"])
        self.assertNotIn("secret@example.com", json.dumps(body))


class Main(unittest.TestCase):
    def test_posts_once_per_new_subscription(self) -> None:
        with mock.patch.object(fsc, "post", return_value="201") as post:
            code, out = run(plan(["create"]), ENV)
        self.assertEqual(code, 0)
        post.assert_called_once()
        api_url, api_key, body = post.call_args.args
        self.assertEqual((api_url, api_key), ("https://api.example.com/", "k-not-printed"))
        self.assertEqual(body["external_id"], fsc.external_id(TOPIC))
        self.assertNotIn("k-not-printed", out)
        self.assertNotIn("secret@example.com", out)

    def test_nothing_new_files_nothing(self) -> None:
        with mock.patch.object(fsc, "post") as post:
            code, out = run(plan(["update"]), ENV)
        self.assertEqual(code, 0)
        post.assert_not_called()
        self.assertIn("nothing to file", out)

    def test_missing_key_warns_and_passes(self) -> None:
        with mock.patch.object(fsc, "post") as post:
            code, out = run(plan(["create"]), {})
        self.assertEqual(code, 0)
        post.assert_not_called()
        self.assertIn("::warning::", out)

    def test_refused_request_warns_and_passes(self) -> None:
        error = urllib.error.HTTPError("u", 403, "Forbidden", None, None)  # type: ignore[arg-type]
        with mock.patch.object(fsc, "post", side_effect=error):
            code, out = run(plan(["create"]), ENV)
        self.assertEqual(code, 0)
        self.assertIn("HTTP 403", out)
        self.assertNotIn("k-not-printed", out)

    def test_unreachable_api_warns_and_passes(self) -> None:
        with mock.patch.object(fsc, "post", side_effect=urllib.error.URLError("down")):
            code, out = run(plan(["create"]), ENV)
        self.assertEqual(code, 0)
        self.assertIn("::warning::", out)


if __name__ == "__main__":
    unittest.main()
