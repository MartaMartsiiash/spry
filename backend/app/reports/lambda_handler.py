"""Builder entry point. The container image runs this instead of the API.

Accepts a direct invoke (``{"week": "2026-W40", "source": "schedule"}``) and an
SQS batch, where that same JSON is ``Records[0].body``. A missing week means
the previous ISO week. The schedule's messages keep ``source=schedule`` so the
log line still says ``trigger=schedule`` after the queue is in front.
"""

import json
import logging
import os

import boto3

from app.reports.weekly import build_weekly_report, normalize_week, previous_iso_week, report_key

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def read_request(event: dict) -> tuple[str, str | None]:
    """Return ``(trigger, week or None)`` from a direct invoke or one SQS record."""
    records = event.get("Records") if isinstance(event, dict) else None
    record = None
    if records and isinstance(records[0], dict) and "body" in records[0]:
        record = records[0]
    if record is not None:
        payload = json.loads(record["body"])
    else:
        payload = event if isinstance(event, dict) else {}
    source = payload.get("source")
    if source == "schedule":
        trigger = "schedule"
    elif record is not None:
        trigger = "sqs"
    else:
        trigger = "direct"
    week = payload.get("week")
    if week is None or week == "":
        return trigger, None
    return trigger, str(week)


def _one(event: dict) -> dict:
    """Build one report and store it. Raises on purpose so SQS can retry."""
    trigger, week_raw = read_request(event)
    week = normalize_week(week_raw) if week_raw else previous_iso_week()
    # The message text itself carries the fields: Lambda's default formatter
    # does not print logging's ``extra`` dict, and the lab asks for this line.
    logger.info("report-builder triggered trigger=%s week=%s", trigger, week)
    forced = os.environ.get("REPORT_FAIL_WEEK", "").strip()
    if forced and forced == week:
        raise RuntimeError(f"forced failure for week {week}")
    body = build_weekly_report(week)
    bucket = os.environ["REPORTS_BUCKET"]
    key = report_key(week)
    boto3.client("s3").put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="text/csv; charset=utf-8",
    )
    logger.info(
        "report-builder saved s3://%s/%s bytes=%s trigger=%s",
        bucket,
        key,
        len(body),
        trigger,
    )
    return {"week": week, "key": key, "trigger": trigger}


def handler(event, context):
    records = event.get("Records") if isinstance(event, dict) else None
    if records and isinstance(records[0], dict) and "body" in records[0]:
        results = []
        for record in records:
            results.append(_one({"Records": [record]}))
        return {"results": results}
    return _one(event)
