"""Queue a weekly report without calling SQS from this VPC.

The API has no NAT, so sqs:SendMessage would need an interface endpoint
(about $7 a month per availability zone). A row in the database would
survive a queue outage, but a poller frequent enough for a button would
keep Aurora awake. Writing ``requests/<id>.json`` through the S3 gateway
endpoint is free: a function outside the VPC turns that file into the same
SQS message the schedule sends. The weakness is that the file is not a
queue; if the notification is lost the JSON sits unread. That is acceptable
for a button used a few times a week. The prefix is ``requests/``, not
``reports/``, so this upload cannot wake the mailer.
"""

import json
import logging
import uuid

import boto3
from botocore.exceptions import ClientError

from app.config import settings
from app.reports.weekly import previous_iso_week

logger = logging.getLogger("meetings.reports")


class ReportsNotConfiguredError(Exception):
    """No reports bucket is configured (local compose, or the stack is not deployed)."""


class ReportsUnavailableError(Exception):
    """The request file could not be stored."""


def enqueue_report(week: str | None) -> dict:
    """Store one request file. ``week`` is already canonical, or None for the previous week."""
    bucket = settings.reports_bucket
    if not bucket:
        raise ReportsNotConfiguredError("Weekly reports are not configured on this server.")
    chosen = week or previous_iso_week()
    request_id = str(uuid.uuid4())
    key = f"requests/{request_id}.json"
    payload = json.dumps({"id": request_id, "week": chosen, "source": "api"}).encode()
    try:
        boto3.client("s3").put_object(
            Bucket=bucket,
            Key=key,
            Body=payload,
            ContentType="application/json",
        )
    except ClientError as exc:
        logger.exception("could not store report request s3://%s/%s", bucket, key)
        raise ReportsUnavailableError("Could not queue the report.") from exc
    return {"id": request_id, "week": chosen, "status": "queued"}
