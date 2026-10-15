"""Turn a request file into the same SQS command the schedule sends.

Triggered by uploads under requests/. It reads the file and never writes one,
so it cannot call itself.
"""

import json
import logging
import os
from urllib.parse import unquote_plus

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    record = event["Records"][0]["s3"]
    bucket = record["bucket"]["name"]
    key = unquote_plus(record["object"]["key"])
    logger.info("report-enqueue triggered trigger=s3 bucket=%s key=%s", bucket, key)
    if not key.startswith("requests/") or not key.endswith(".json"):
        logger.info("report-enqueue skipped key=%s", key)
        return {"skipped": key}
    response = boto3.client("s3").get_object(Bucket=bucket, Key=key)
    try:
        payload = json.loads(response["Body"].read())
    finally:
        response["Body"].close()
    message = {"week": payload.get("week"), "source": payload.get("source") or "api"}
    boto3.client("sqs").send_message(
        QueueUrl=os.environ["QUEUE_URL"],
        MessageBody=json.dumps(message),
    )
    logger.info("report-enqueue sent trigger=s3 week=%s", message["week"])
    return message
