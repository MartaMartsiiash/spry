#!/usr/bin/env bash
# Push payment JSON lines to SQS via AWS CLI (avoids boto3 CRT login dep).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$(dirname "$0")/env.sh"

FILE="${1:-$ROOT/data/payments/dt=2026-10-01/events.jsonl}"
LIMIT="${2:-2500}"
FAIL_BOOST="${3:-0.30}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$FILE" "$LIMIT" "$FAIL_BOOST" "$TMP" <<'PY'
import json, random, sys
from datetime import datetime
from pathlib import Path

path, limit, boost, out = Path(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]), Path(sys.argv[4])

def parse_ts(v):
    return datetime.fromisoformat(v.replace("Z", "+00:00"))

events = []
with path.open() as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        events.append(json.loads(line))
        if len(events) >= limit:
            break
events.sort(key=lambda e: parse_ts(e["modifiedDate"]))

batch_idx = 0
batch = []

def flush():
    global batch_idx, batch
    if not batch:
        return
    entries = []
    for i, ev in enumerate(batch):
        body = json.dumps(ev, separators=(",", ":"))
        # Escape for AWS CLI JSON
        entries.append({"Id": str(i), "MessageBody": body})
    (out / f"batch-{batch_idx:05d}.json").write_text(json.dumps(entries))
    batch_idx += 1
    batch = []

for ev in events:
    if boost and ev.get("status") in {"success", "failure"} and random.random() < boost:
        ev = dict(ev)
        ev["status"] = "failure"
        ev["failureReason"] = ev.get("failureReason") or "Simulated failure"
        ev["finalAmount"] = 0
    batch.append(ev)
    if len(batch) >= 10:
        flush()
flush()
print(f"batches={batch_idx} events={len(events)}", flush=True)
PY

sent=0
for f in "$TMP"/batch-*.json; do
  aws sqs send-message-batch --queue-url "$QUEUE_URL" --entries "file://$f" --region "$REGION" >/dev/null
  sent=$((sent + $(python3 -c "import json;print(len(json.load(open('$f'))))")) )
  echo "sent=$sent"
done
echo "DONE sent=$sent"
