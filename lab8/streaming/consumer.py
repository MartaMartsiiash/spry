#!/usr/bin/env python3
"""
Event-time 1-minute windows over payments topic.
- Drop exact duplicates
- Track latest status per invoiceId within the window
- Failure share per paymentMethod; alert if > 10%
- Late arrivals: wait `late_grace_sec` after window end (event-time watermark)
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from kafka import KafkaConsumer

BROKERS = "127.0.0.1:19092"
TOPIC = "payments"


def parse_ts(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def floor_minute(ts: datetime) -> datetime:
    return ts.replace(second=0, microsecond=0)


@dataclass
class Window:
    start: datetime
    seen_lines: set[str] = field(default_factory=set)
    # invoiceId -> (modifiedDate, status, paymentMethod)
    latest: dict[str, tuple[datetime, str, str]] = field(default_factory=dict)
    rejected_late: int = 0

    def end(self) -> datetime:
        return self.start + timedelta(minutes=1)


class Processor:
    def __init__(self, late_grace_sec: int, alert_threshold: float = 0.10):
        self.late_grace_sec = late_grace_sec
        self.alert_threshold = alert_threshold
        self.windows: dict[datetime, Window] = {}
        self.closed = 0
        self.alerts = 0
        self.total_events = 0
        self.duplicates = 0
        self.rejected_late_total = 0
        self.watermark: datetime | None = None

    def handle(self, raw: bytes, event: dict) -> None:
        self.total_events += 1
        line = raw.decode("utf-8")
        event_time = parse_ts(event["modifiedDate"])
        win_start = floor_minute(event_time)

        if self.watermark is None or event_time > self.watermark:
            self.watermark = event_time

        # Reject events for windows already past watermark - grace
        close_at = win_start + timedelta(minutes=1, seconds=self.late_grace_sec)
        if self.watermark is not None and self.watermark >= close_at and win_start not in self.windows:
            # late arrival after window was eligible to close and already gone
            self.rejected_late_total += 1
            return

        win = self.windows.get(win_start)
        if win is None:
            # If watermark already past close_at, reject (late)
            if self.watermark is not None and self.watermark >= close_at:
                self.rejected_late_total += 1
                return
            win = Window(start=win_start)
            self.windows[win_start] = win

        if line in win.seen_lines:
            self.duplicates += 1
            return
        win.seen_lines.add(line)

        inv = event["invoiceId"]
        status = event["status"]
        method = event["paymentMethod"]
        prev = win.latest.get(inv)
        if prev is None or event_time >= prev[0]:
            win.latest[inv] = (event_time, status, method)

        self.maybe_close()

    def maybe_close(self) -> None:
        if self.watermark is None:
            return
        to_close = []
        for start, win in self.windows.items():
            close_at = win.end() + timedelta(seconds=self.late_grace_sec)
            if self.watermark >= close_at:
                to_close.append(start)
        for start in sorted(to_close):
            self.close_window(self.windows.pop(start))

    def close_window(self, win: Window) -> None:
        self.closed += 1
        by_method: dict[str, list[str]] = defaultdict(list)
        for _inv, (_ts, status, method) in win.latest.items():
            by_method[method].append(status)

        print(f"\n=== WINDOW {win.start.isoformat()} → {win.end().isoformat()} ===", flush=True)
        print(
            f"invoices={len(win.latest)} unique_lines={len(win.seen_lines)} rejected_late={win.rejected_late}",
            flush=True,
        )
        for method, statuses in sorted(by_method.items()):
            n = len(statuses)
            fails = sum(1 for s in statuses if s == "failure")
            rate = fails / n if n else 0.0
            flag = ""
            if rate > self.alert_threshold:
                self.alerts += 1
                flag = "  *** ALERT: failures > 10% ***"
            print(
                f"  {method}: n={n} failures={fails} rate={rate:.1%}{flag}",
                flush=True,
            )

    def flush_all(self) -> None:
        for start in sorted(list(self.windows.keys())):
            self.close_window(self.windows.pop(start))
        print(
            f"\nSUMMARY closed_windows={self.closed} alerts={self.alerts} "
            f"events={self.total_events} duplicates={self.duplicates} "
            f"rejected_late_total={self.rejected_late_total}",
            flush=True,
        )


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--group", default="lab8-payments")
    p.add_argument("--late-grace-sec", type=int, default=120)
    p.add_argument("--max-messages", type=int, default=0, help="0 = run until idle timeout")
    p.add_argument("--idle-sec", type=float, default=8.0)
    args = p.parse_args()

    consumer = KafkaConsumer(
        TOPIC,
        bootstrap_servers=BROKERS,
        group_id=args.group,
        auto_offset_reset="earliest",
        enable_auto_commit=True,
        consumer_timeout_ms=int(args.idle_sec * 1000),
        key_deserializer=lambda k: k.decode("utf-8") if k else None,
        value_deserializer=lambda v: v,  # raw for duplicate detection
    )

    proc = Processor(late_grace_sec=args.late_grace_sec)
    print(
        f"consuming topic={TOPIC} group={args.group} late_grace_sec={args.late_grace_sec}",
        flush=True,
    )

    n = 0
    try:
        for msg in consumer:
            raw = msg.value
            event = json.loads(raw.decode("utf-8"))
            proc.handle(raw, event)
            n += 1
            if args.max_messages and n >= args.max_messages:
                break
    except KeyboardInterrupt:
        print("interrupted", flush=True)
    finally:
        proc.flush_all()
        parts = consumer.assignment()
        print("assigned_partitions=", sorted(str(tp) for tp in parts), flush=True)
        consumer.close()


if __name__ == "__main__":
    main()
