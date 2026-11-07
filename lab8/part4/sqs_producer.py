#!/usr/bin/env python3
"""Push payment events to SQS (cloud stream stand-in for Kinesis)."""

from __future__ import annotations

import argparse
import json
import os
import random
import time
from datetime import datetime
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

REGION = os.environ.get("REGION", "eu-north-1")


def parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument(
        "--file",
        default=str(
            Path(__file__).resolve().parents[1]
            / "data"
            / "payments"
            / "dt=2026-10-01"
            / "events.jsonl"
        ),
    )
    p.add_argument("--queue-url", default=os.environ.get("QUEUE_URL", ""))
    p.add_argument("--limit", type=int, default=2000)
    p.add_argument("--rate", type=float, default=100.0)
    p.add_argument("--fail-boost", type=float, default=0.25)
    args = p.parse_args()
    if not args.queue_url:
        raise SystemExit("QUEUE_URL required")

    sqs = boto3.client("sqs", region_name=REGION)
    events = []
    with Path(args.file).open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            events.append(json.loads(line))
            if args.limit and len(events) >= args.limit:
                break
    events.sort(key=lambda e: parse_ts(e["modifiedDate"]))

    interval = 1.0 / args.rate if args.rate > 0 else 0.0
    sent = 0
    t0 = time.time()
    batch: list[dict] = []

    def flush() -> None:
        nonlocal batch, sent
        if not batch:
            return
        entries = []
        for i, ev in enumerate(batch):
            entries.append(
                {
                    "Id": str(i),
                    "MessageBody": json.dumps(ev, separators=(",", ":")),
                    "MessageGroupId": None,
                }
            )
        # Drop MessageGroupId for standard queue
        for e in entries:
            e.pop("MessageGroupId", None)
        try:
            sqs.send_message_batch(QueueUrl=args.queue_url, Entries=entries)
        except ClientError as exc:
            raise SystemExit(f"send_message_batch failed: {exc}") from exc
        sent += len(batch)
        print(f"sent={sent}", flush=True)
        batch = []

    for ev in events:
        if args.fail_boost and ev.get("status") in {"success", "failure"}:
            if random.random() < args.fail_boost:
                ev = dict(ev)
                ev["status"] = "failure"
                ev["failureReason"] = ev.get("failureReason") or "Simulated failure"
                ev["finalAmount"] = 0
        batch.append(ev)
        if len(batch) >= 10:
            flush()
            if interval:
                time.sleep(interval * 10)
    flush()
    dt = time.time() - t0
    print(f"DONE sent={sent} seconds={dt:.1f}", flush=True)


if __name__ == "__main__":
    main()
