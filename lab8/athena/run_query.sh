#!/usr/bin/env bash
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-spry}"
export AWS_REGION="${AWS_REGION:-eu-north-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

SQL_FILE="${1:?usage: run_query.sh file.sql [database]}"
DB="${2:-lab8}"
OUT="s3://successfulsuccess-lab8-payments-378600555796/athena-results/"
LABEL="$(basename "$SQL_FILE")"

ARGS=(--query-string "file://$SQL_FILE" --result-configuration "OutputLocation=$OUT" --work-group primary --query QueryExecutionId --output text)
if [[ -n "$DB" && "$DB" != "-" ]]; then
  ARGS+=(--query-execution-context "Database=$DB")
fi

QID=$(aws athena start-query-execution "${ARGS[@]}")
echo "=== $LABEL qid=$QID"

while true; do
  STATE=$(aws athena get-query-execution --query-execution-id "$QID" --query 'QueryExecution.Status.State' --output text)
  case "$STATE" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
  sleep 2
done

aws athena get-query-execution --query-execution-id "$QID" --output json > "${SQL_FILE%.sql}.meta.json"
python3 - "$SQL_FILE" "$QID" "$STATE" <<'PY'
import json, sys
from pathlib import Path
sql_file, qid, state = sys.argv[1], sys.argv[2], sys.argv[3]
meta = json.loads(Path(sql_file).with_suffix(".meta.json").read_text())
qe = meta["QueryExecution"]
stats = qe.get("Statistics", {})
print("state=", state)
reason = qe["Status"].get("StateChangeReason")
if reason:
    print("reason=", reason[:800])
print("data_scanned_bytes=", stats.get("DataScannedInBytes"))
print("engine_ms=", stats.get("EngineExecutionTimeInMillis"))
print("total_ms=", stats.get("TotalExecutionTimeInMillis"))
summary = {
    "file": Path(sql_file).name,
    "qid": qid,
    "state": state,
    "data_scanned_bytes": stats.get("DataScannedInBytes"),
    "engine_ms": stats.get("EngineExecutionTimeInMillis"),
    "total_ms": stats.get("TotalExecutionTimeInMillis"),
    "reason": reason,
}
Path(sql_file).with_suffix(".summary.json").write_text(json.dumps(summary, indent=2) + "\n")
PY

if [[ "$STATE" != "SUCCEEDED" ]]; then
  exit 1
fi

aws athena get-query-results --query-execution-id "$QID" --max-items 40 --output json \
  | python3 - "$SQL_FILE" <<'PY'
import json, sys
from pathlib import Path
sql_file = sys.argv[1]
data = json.load(sys.stdin)
lines = []
for row in data.get("ResultSet", {}).get("Rows", []):
    line = " | ".join(d.get("VarCharValue", "") for d in row.get("Data", []))
    lines.append(line)
    print(line)
Path(sql_file).with_suffix(".preview.txt").write_text("\n".join(lines) + "\n")
PY
