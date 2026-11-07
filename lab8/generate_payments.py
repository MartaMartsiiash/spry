#!/usr/bin/env python3
"""Generate Lab 8–style payment webhook events (JSON Lines), partitioned by dt.

Rough scale: ~3e6 events across 2026-10-01 .. 2026-10-31.
~1% exact duplicate lines, ~2% late arrivals (receivedAt 1–10 min after modifiedDate).
"""

from __future__ import annotations

import json
import random
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

OUT = Path(__file__).resolve().parent / "data" / "payments"
START = date(2026, 10, 1)
DAYS = 31
# ~96k events/day → ~3.0M total
EVENTS_PER_DAY = 97_000
DUP_RATE = 0.01
LATE_RATE = 0.02

MERCHANTS = [
    ("m_001", "Rozetka", "5411"),
    ("m_002", "Silpo", "5411"),
    ("m_003", "Uklon Ride", "4121"),
    ("m_004", "Nova Poshta", "4215"),
    ("m_005", "Foxtrot", "5732"),
    ("m_006", "Starbucks UA", "5814"),
    ("m_007", "Olx Services", "7399"),
    ("m_008", "Kyivstar", "4814"),
]
METHODS = ["apple_pay", "google_pay", "card", "monobank"]
DEVICES = ["ios", "android", "web"]
FAIL_REASONS = [
    "Insufficient funds",
    "Card declined",
    "Timeout",
    "Fraud suspected",
    "Limit exceeded",
]


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def emit_payment(rng: random.Random, day: date, lines: list[str]) -> None:
    invoice = str(uuid.UUID(int=rng.getrandbits(128), version=4))
    merchant_id, merchant_name, mcc = MERCHANTS[rng.randrange(len(MERCHANTS))]
    method = METHODS[rng.randrange(len(METHODS))]
    device = DEVICES[rng.randrange(len(DEVICES))]
    customer = f"c_{rng.randrange(1, 200_000):06d}"
    reference = f"ord-{rng.randrange(10_000_000, 99_999_999)}"
    amount = rng.choice([9900, 14900, 19900, 25000, 49900, 100000, 250000, 99900])
    ccy = 980

    hour = rng.randrange(0, 24)
    minute = rng.randrange(0, 60)
    second = rng.randrange(0, 60)
    created = datetime(day.year, day.month, day.day, hour, minute, second, tzinfo=timezone.utc)

    def base(**extra):
        row = {
            "invoiceId": invoice,
            "amount": amount,
            "finalAmount": 0,
            "ccy": ccy,
            "reference": reference,
            "createdDate": iso(created),
            "merchantId": merchant_id,
            "merchantName": merchant_name,
            "mcc": mcc,
            "customerId": customer,
            "paymentMethod": method,
            "device": device,
        }
        row.update(extra)
        return row

    def add(row: dict, modified: datetime) -> None:
        received = modified
        if rng.random() < LATE_RATE:
            received = modified + timedelta(seconds=rng.randint(60, 600))
        row = dict(row)
        row["modifiedDate"] = iso(modified)
        row["receivedAt"] = iso(received)
        line = json.dumps(row, separators=(",", ":"))
        lines.append(line)
        if rng.random() < DUP_RATE:
            lines.append(line)

    # created
    t0 = created
    add(base(status="created"), t0)

    # processing
    t1 = t0 + timedelta(seconds=rng.randint(1, 30))
    add(base(status="processing"), t1)

    # terminal
    fail = rng.random() < 0.08
    t2 = t1 + timedelta(seconds=rng.randint(1, 120))
    if fail:
        add(
            base(status="failure", failureReason=FAIL_REASONS[rng.randrange(len(FAIL_REASONS))]),
            t2,
        )
    else:
        add(base(status="success", finalAmount=amount), t2)


def generate_day(day: date, seed: int) -> Path:
    rng = random.Random(seed)
    lines: list[str] = []
    # keep generating payments until we hit the event budget
    while len(lines) < EVENTS_PER_DAY:
        emit_payment(rng, day, lines)
    lines = lines[:EVENTS_PER_DAY]
    rng.shuffle(lines)

    part = OUT / f"dt={day.isoformat()}"
    part.mkdir(parents=True, exist_ok=True)
    path = part / "events.jsonl"
    with path.open("w", encoding="utf-8") as f:
        f.write("\n".join(lines))
        f.write("\n")
    return path


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    for i in range(DAYS):
        day = START + timedelta(days=i)
        path = generate_day(day, seed=20261000 + i)
        n = sum(1 for _ in path.open())
        total += n
        print(f"{day.isoformat()} -> {path} ({n} lines)", flush=True)
    print(f"TOTAL_EVENTS={total}", flush=True)


if __name__ == "__main__":
    main()
