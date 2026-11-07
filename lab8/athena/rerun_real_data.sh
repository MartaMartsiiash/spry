#!/usr/bin/env bash
# Lab 8 Part 2 on the OFFICIAL dataset, as the assignment requires:
#   copy s3://ucu-ooad-lab8-payments/payments/ into an own bucket in us-east-1,
#   rerun all Athena queries there (results -> athena_real/), then run a Glue Crawler (Way B).
# Usage:  cd lab8/athena && bash rerun_real_data.sh
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-spry}"
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="successfulsuccess-lab8-use1-${ACCOUNT}"
OLD_BUCKET="successfulsuccess-lab8-payments-378600555796"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$HERE/athena_real"
mkdir -p "$OUTDIR"

step() { echo; echo "##### $*"; }

# ---------- 1. bucket + copy (same region = free) ----------
step "1. Bucket $BUCKET in us-east-1"
aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null || aws s3 mb "s3://$BUCKET" --region us-east-1

step "2. Copy official dataset (1.2 GB, a few minutes)"
aws s3 sync s3://ucu-ooad-lab8-payments/payments/ "s3://$BUCKET/payments/" --region us-east-1 --only-show-errors
aws s3 ls "s3://$BUCKET/payments/" | head -3
echo "partitions: $(aws s3 ls "s3://$BUCKET/payments/" | wc -l)"

# ---------- 2. Athena runner ----------
run() {   # run <name> <sql-file>
  local name="$1" file="$2"
  local qid state
  qid=$(aws athena start-query-execution \
        --query-string "file://$file" \
        --query-execution-context Database=lab8 \
        --result-configuration "OutputLocation=s3://$BUCKET/athena-results/" \
        --work-group primary --query QueryExecutionId --output text)
  while true; do
    state=$(aws athena get-query-execution --query-execution-id "$qid" --query 'QueryExecution.Status.State' --output text)
    case "$state" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
    sleep 2
  done
  aws athena get-query-execution --query-execution-id "$qid" \
    --query 'QueryExecution.{state:Status.State,reason:Status.StateChangeReason,data_scanned_bytes:Statistics.DataScannedInBytes,engine_ms:Statistics.EngineExecutionTimeInMillis,total_ms:Statistics.TotalExecutionTimeInMillis}' \
    --output json > "$OUTDIR/$name.summary.json"
  {
    echo "-- $name  qid=$qid  state=$state"
    cat "$OUTDIR/$name.summary.json"
    if [[ "$state" == SUCCEEDED ]]; then
      aws athena get-query-results --query-execution-id "$qid" --max-items 40 --output json \
        | python3 -c "import json,sys; [print(' | '.join(d.get('VarCharValue','') for d in r['Data'])) for r in json.load(sys.stdin)['ResultSet']['Rows']]"
    fi
  } | tee "$OUTDIR/$name.txt"
  [[ "$state" == SUCCEEDED ]] || { echo "!! $name failed"; return 1; }
}

sql() {   # copy a query, pointing it at the new bucket
  sed "s#$OLD_BUCKET#$BUCKET#g" "$HERE/$1.sql" > "$OUTDIR/$1.sql"
  echo "$OUTDIR/$1.sql"
}

step "3. Database, table, partitions"
echo "CREATE DATABASE IF NOT EXISTS lab8" > "$OUTDIR/00_create_db.sql"
aws athena start-query-execution --query-string "CREATE DATABASE IF NOT EXISTS lab8" \
  --result-configuration "OutputLocation=s3://$BUCKET/athena-results/" >/dev/null
sleep 3
run 01_create_table "$(sql 01_create_table)"
run 01b_msck        "$(sql 01b_msck)"

step "4. Scale"
run 00_count        "$(sql 00_count)"
run 00_scale        "$(sql 00_scale)"
run 00_duplicates   "$(sql 00_duplicates)"
run 00_late_hour    "$(sql 00_late_hour)"

step "5. Queries 2-7"
run 02_payments_view "$(sql 02_payments_view)"
echo "SELECT COUNT(*) AS payments, COUNT(DISTINCT invoiceId) AS invoices FROM lab8.payments" > "$OUTDIR/02_count.sql"
run 02_count        "$OUTDIR/02_count.sql"
run 03_turnover     "$(sql 03_turnover)"
run 04_failure_rate "$(sql 04_failure_rate)"
run 05_peak_hours   "$(sql 05_peak_hours)"
cat > "$OUTDIR/06_late_events.sql" <<'Q'
SELECT COUNT(*) AS events,
       SUM(CASE WHEN date_diff('second', from_iso8601_timestamp(modifiedDate), from_iso8601_timestamp(receivedAt)) > 60 THEN 1 ELSE 0 END) AS late_over_60s
FROM lab8.payment_events
Q
run 06_late_events  "$OUTDIR/06_late_events.sql"
run 07_ctas_parquet "$(sql 07_ctas_parquet)"
run 03_turnover_parquet     "$(sql 03_turnover_parquet)"
run 04_failure_rate_parquet "$(sql 04_failure_rate_parquet)"
run 05_peak_hours_parquet   "$(sql 05_peak_hours_parquet)"

# ---------- 3. Way B: Glue Crawler ----------
step "6. Glue Crawler"
ROLE=lab8-glue-crawler-role
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
  sleep 10   # IAM propagation
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name lab8-s3-read --policy-document \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::$BUCKET\",\"arn:aws:s3:::$BUCKET/payments/*\"]}]}"
sleep 5
aws glue get-crawler --name lab8-payments-crawler >/dev/null 2>&1 || \
  aws glue create-crawler --name lab8-payments-crawler \
    --role "arn:aws:iam::${ACCOUNT}:role/$ROLE" --database-name lab8 --table-prefix crawled_ \
    --targets "{\"S3Targets\":[{\"Path\":\"s3://$BUCKET/payments/\"}]}"
aws glue start-crawler --name lab8-payments-crawler
echo "crawler running (1-3 min)..."
sleep 20
while [[ "$(aws glue get-crawler --name lab8-payments-crawler --query Crawler.State --output text)" != READY ]]; do sleep 10; done
aws glue get-crawler --name lab8-payments-crawler --query 'Crawler.LastCrawl' --output json
TABLE=$(aws glue get-tables --database-name lab8 --query "TableList[?starts_with(Name,'crawled_')].Name | [0]" --output text)
echo "crawled table: $TABLE"
aws glue get-table --database-name lab8 --name "$TABLE" \
  --query 'Table.{columns:StorageDescriptor.Columns,partitions:PartitionKeys,serde:StorageDescriptor.SerdeInfo.SerializationLibrary}' \
  --output json | tee "$OUTDIR/crawled_schema.json"
echo "SELECT COUNT(*) AS events, COUNT(failureReason) AS with_failure_reason FROM lab8.$TABLE" > "$OUTDIR/08_crawled_count.sql"
run 08_crawled_count "$OUTDIR/08_crawled_count.sql"

step "DONE — results in $OUTDIR"
