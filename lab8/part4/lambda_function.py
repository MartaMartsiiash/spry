"""SQS → S3 (JSONL) + SNS alert when batch failure share > 10%."""

from __future__ import annotations

import json
import os
import uuid
from collections import defaultdict
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")
sns = boto3.client("sns")

BUCKET = os.environ["BUCKET"]
PREFIX = os.environ.get("STREAM_PREFIX", "stream")
TOPIC_ARN = os.environ["TOPIC_ARN"]
ALERT_THRESHOLD = float(os.environ.get("ALERT_THRESHOLD", "0.10"))


def handler(event, _context):
    lines: list[str] = []
    by_method: dict[str, list[str]] = defaultdict(list)
    seen: set[str] = set()
    duplicates = 0

    for record in event.get("Records", []):
        body = record.get("body", "")
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            continue
        # Support raw event or { "event": {...} }
        ev = payload.get("event", payload)
        raw = json.dumps(ev, separators=(",", ":"), ensure_ascii=False)
        if raw in seen:
            duplicates += 1
            continue
        seen.add(raw)
        lines.append(raw)
        method = ev.get("paymentMethod", "unknown")
        status = ev.get("status", "unknown")
        by_method[method].append(status)

    if lines:
        now = datetime.now(timezone.utc)
        key = (
            f"{PREFIX}/raw/dt={now.strftime('%Y-%m-%d')}/hour={now.strftime('%H')}/"
            f"batch-{now.strftime('%Y%m%dT%H%M%S')}-{uuid.uuid4().hex[:8]}.jsonl"
        )
        s3.put_object(
            Bucket=BUCKET,
            Key=key,
            Body=("\n".join(lines) + "\n").encode("utf-8"),
            ContentType="application/x-ndjson",
        )
    else:
        key = None

    alerts = []
    for method, statuses in sorted(by_method.items()):
        n = len(statuses)
        fails = sum(1 for s in statuses if s == "failure")
        rate = fails / n if n else 0.0
        if rate > ALERT_THRESHOLD:
            msg = f"ALERT method={method} failures={fails}/{n} rate={rate:.1%}"
            alerts.append(msg)
            sns.publish(
                TopicArn=TOPIC_ARN,
                Subject=f"lab8 payment alert: {method}",
                Message=msg,
            )

    return {
        "written": len(lines),
        "duplicates": duplicates,
        "s3_key": key,
        "alerts": alerts,
    }
