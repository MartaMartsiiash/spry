#!/usr/bin/env bash
# Run one Athena query file; print QueryExecutionId, state, DataScanned, runtime, and preview.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-spry}"
export AWS_REGION="${AWS_REGION:-eu-north-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"

BUCKET="successfulsuccess-lab8-payments-378600555796"
OUTPUT="s3://${BUCKET}/athena-results/"
DB="${ATHENA_DB:-lab8}"
WG="${ATHENA_WG:-primary}"
SQL_FILE="${1:?usage: run_athena.sh query.sql}"
LABEL="${2:-$(basename "$SQL_FILE")}"

SQL=$(cat "$SQL_FILE")
QID=$(aws athena start-query-execution \
  --query-string "$SQL" \
  --query-execution-context "Database=$DB" \
  --result-configuration "OutputLocation=$OUTPUT" \
  --work-group "$WG" \
  --query 'QueryExecutionId' --output text)

echo "=== $LABEL qid=$QID ==="
while true; do
  STATE=$(aws athena get-query-execution --query-execution-id "$QID" \
    --query 'QueryExecution.Status.State' --output text)
  case "$STATE" in
    SUCCEEDED|FAILED|CANCELLED) break ;;
  esac
  sleep 2
done

META=$(aws athena get-query-execution --query-execution-id "$QID" --output json)
python3 - <<PY
import json
m=json.loads('''$META'''.replace("'''","'")) if False else json.loads(open('/dev/stdin').read()) if False else None
PY

python3 -c "
import json,sys
m=json.load(sys.stdin)
qe=m['QueryExecution']
st=qe['Status']
stats=qe.get('Statistics',{})
print('state=', st['State'])
if st.get('StateChangeReason'):
  print('reason=', st['StateChangeReason'][:500])
print('data_scanned_bytes=', stats.get('DataScannedInBytes'))
print('engine_ms=', stats.get('EngineExecutionTimeInMillis'))
print('total_ms=', stats.get('TotalExecutionTimeInMillis'))
" <<<"$META"

if [[ "$(python3 -c "import json,sys; print(json.load(sys.stdin)['QueryExecution']['Status']['State'])" <<<"$META")" == "SUCCEEDED" ]]; then
  aws athena get-query-results --query-execution-id "$QID" --max-items 30 --output json \
    | python3 -c "
import json,sys
r=json.load(sys.stdin)
rows=r.get('ResultSet',{}).get('Rows',[])
for row in rows[:25]:
  print(' | '.join(d.get('VarCharValue','') for d in row.get('Data',[])))
"
fi
