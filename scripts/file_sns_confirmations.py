#!/usr/bin/env python3
"""File a person task for each SNS email subscription an apply created.

    terraform show -json tfplan > plan.json   # the plan that was applied
    terraform show -json > state.json         # the state after it
    python3 scripts/file_sns_confirmations.py plan.json state.json

A new aws_sns_topic_subscription with the email protocol stays
PendingConfirmation until someone clicks the link AWS emails, and until
then the alarm on that topic delivers nothing. The apply job runs this
after a successful apply, so that step is a task on the board instead of
a line in a file someone has to remember.

Each task is filed through POST /v1/tasks as the infra-apply machine
(INFRA_APPLY_API_KEY, task-filer only) at INFRA_APPLY_API_URL. The
external id is derived from the topic ARN, so a re-run files nothing new.

Never fails the apply: a missing key, an unreachable API or a refused
request is a warning, and the script exits 0. The key is never printed,
and neither is the alert address (a sensitive variable).
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from collections.abc import Iterator
from pathlib import Path

SOURCE = "infra-apply"
RESOURCE_TYPE = "aws_sns_topic_subscription"

#: Identifies this client to the API's edge. Not cosmetic: the API sits
#: behind Cloudflare, whose Browser Integrity Check refuses urllib's default
#: User-Agent with a 1010 that never reaches the API.
USER_AGENT = "infra-apply/1 (+https://github.com/mini-app-polis/infra)"


def created_subscriptions(plan: dict) -> list[str]:
    """Addresses of the email subscriptions the plan creates."""
    addresses = []
    for change in plan.get("resource_changes", []):
        if change.get("type") != RESOURCE_TYPE:
            continue
        actions = change.get("change", {}).get("actions", [])
        after = change.get("change", {}).get("after") or {}
        if "create" in actions and after.get("protocol") == "email":
            addresses.append(change["address"])
    return addresses


def _resources(module: dict) -> Iterator[dict]:
    yield from module.get("resources", [])
    for child in module.get("child_modules", []):
        yield from _resources(child)


def state_values(state: dict) -> dict[str, dict]:
    """Every resource's values in the state, by address."""
    root = state.get("values", {}).get("root_module", {})
    return {r["address"]: r.get("values", {}) for r in _resources(root)}


def external_id(topic_arn: str) -> str:
    """The task's key: one per topic, so a re-run files nothing new."""
    digest = hashlib.sha256(topic_arn.encode()).hexdigest()[:16]
    return f"{SOURCE}.sns-confirm.{digest}"


def task_request(topic_arn: str) -> dict:
    """The POST /v1/tasks body (TaskCreateRequest) for one subscription."""
    topic = topic_arn.rsplit(":", 1)[-1]
    return {
        "source": SOURCE,
        "external_id": external_id(topic_arn),
        "draft": {
            "title": f"Confirm the SNS alert subscription to {topic}",
            "where": "AWS SNS",
            "done_when": (
                f"The email subscription to {topic} shows Confirmed in the SNS "
                "console (not PendingConfirmation)."
            ),
            "constraints": "None",
            "effort": "S",
            "body": (
                f"An infra apply subscribed the alert address to {topic_arn}. AWS "
                "sent it a confirmation email; the subscription delivers "
                "nothing until its link is clicked. Click Confirm subscription in "
                "the email from AWS Notifications, or find the subscription in the "
                "SNS console and request confirmation again if the email is gone."
            ),
            "labels": ["person"],
        },
    }


def post(api_url: str, api_key: str, body: dict) -> str:
    """POST one task request; the API's answer, for the log."""
    request = urllib.request.Request(
        f"{api_url.rstrip('/')}/v1/tasks",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return f"{response.status}"


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    plan = json.loads(Path(argv[1]).read_text())
    state = json.loads(Path(argv[2]).read_text())

    addresses = created_subscriptions(plan)
    if not addresses:
        print("No new email subscriptions: nothing to file.")
        return 0

    api_url = os.environ.get("INFRA_APPLY_API_URL", "")
    api_key = os.environ.get("INFRA_APPLY_API_KEY", "")
    if not api_url or not api_key:
        print(
            "::warning::New SNS email subscriptions need confirming, but "
            "INFRA_APPLY_API_URL or INFRA_APPLY_API_KEY is unset; no task filed: "
            + ", ".join(addresses)
        )
        return 0

    values = state_values(state)
    for address in addresses:
        subscription = values.get(address, {})
        topic_arn = subscription.get("topic_arn")
        if not topic_arn:
            print(f"::warning::{address} is not in the state after the apply; no task filed.")
            continue
        body = task_request(topic_arn)
        try:
            status = post(api_url, api_key, body)
        except urllib.error.HTTPError as exc:
            print(f"::warning::Filing the confirmation task for {address} was refused: HTTP {exc.code}.")
            continue
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            print(f"::warning::Filing the confirmation task for {address} failed: {exc}.")
            continue
        print(f"Filed the confirmation task for {address} ({body['external_id']}): HTTP {status}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
