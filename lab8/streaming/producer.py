#!/usr/bin/env python3
"""Replay payment events into Redpanda topic `payments`, keyed by invoiceId."""

from __future__ import annotations

import argparse
import json
import random
import time
from datetime import datetime, timedelta
from pathlib import Path

from kafka import KafkaProducer

BROKERS = "127.0.0.1:19092"
TOPIC = "payments"


def parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_events(path: Path) -> list[dict]:
    events = []
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            events.append(json.loads(line))
    # Event-time order keeps watermark monotonic for normal runs.
    events.sort(key=lambda e: parse_ts(e["modifiedDate"]))
    return events


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
    p.add_argument("--rate", type=float, default=20.0, help="payments (invoice groups) per second")
    p.add_argument("--limit", type=int, default=0, help="max events (0 = all)")
    p.add_argument(
        "--fail-boost",
        type=float,
        default=0.0,
        help="probability to flip success/processing terminal to failure (experiment 3)",
    )
    p.add_argument(
        "--inject-late",
        type=int,
        default=0,
        help="re-send N events that are ~45-90s behind the watermark (late arrivals)",
    )
    args = p.parse_args()

    events = load_events(Path(args.file))
    if args.limit:
        events = events[: args.limit]

    producer = KafkaProducer(
        bootstrap_servers=BROKERS,
        key_serializer=lambda k: k.encode("utf-8"),
        value_serializer=lambda v: json.dumps(v, separators=(",", ":")).encode("utf-8"),
        acks="all",
        linger_ms=5,
    )

    interval = 1.0 / args.rate if args.rate > 0 else 0.0
    sent = 0
    late_sent = 0
    last_invoice = None
    t0 = time.time()
    recent: list[tuple[datetime, dict]] = []

    def send_one(ev: dict) -> None:
        nonlocal sent, last_invoice
        if args.fail_boost and ev.get("status") in {"success", "failure"}:
            if random.random() < args.fail_boost:
                ev = dict(ev)
                ev["status"] = "failure"
                ev["failureReason"] = ev.get("failureReason") or "Simulated failure"
                ev["finalAmount"] = 0

        key = ev["invoiceId"]
        if last_invoice is not None and key != last_invoice and interval > 0:
            time.sleep(interval)
        last_invoice = key
        producer.send(TOPIC, key=key, value=ev)
        sent += 1
        if sent % 1000 == 0:
            print(f"sent={sent}", flush=True)

    for ev in events:
        ts = parse_ts(ev["modifiedDate"])
        send_one(ev)
        recent.append((ts, ev))
        # Keep ~3 minutes of history for late injection.
        cutoff = ts - timedelta(seconds=180)
        while recent and recent[0][0] < cutoff:
            recent.pop(0)

        if args.inject_late and late_sent < args.inject_late and len(recent) > 10:
            # Prefer events ~45–90s behind current event-time → rejected with grace=0,
            # still accepted with grace=120.
            lo = ts - timedelta(seconds=90)
            hi = ts - timedelta(seconds=45)
            candidates = [e for (t, e) in recent if lo <= t <= hi]
            if candidates and random.random() < 0.15:
                send_one(dict(random.choice(candidates)))
                late_sent += 1

    producer.flush()
    dt = time.time() - t0
    print(
        f"DONE sent={sent} late_injected={late_sent} "
        f"seconds={dt:.1f} rate_events_per_s={sent / dt if dt else 0:.1f}",
        flush=True,
    )


if __name__ == "__main__":
    main()
