"""Email the CSV that S3 just saved. Never writes back under reports/."""

import logging
import os
from email.message import EmailMessage
from urllib.parse import unquote_plus

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def build_raw_message(sender: str, recipients: list[str], key: str, payload: bytes) -> bytes:
    name = key.rsplit("/", 1)[-1]
    message = EmailMessage()
    message["Subject"] = f"Weekly meetings report {name}"
    message["From"] = sender
    message["To"] = ", ".join(recipients)
    message.set_content(f"The weekly meetings report is attached ({key}).")
    message.add_attachment(payload, maintype="text", subtype="csv", filename=name)
    return message.as_bytes()


def handler(event, context):
    record = event["Records"][0]["s3"]
    bucket = record["bucket"]["name"]
    key = unquote_plus(record["object"]["key"])
    logger.info("report-mailer triggered trigger=s3 bucket=%s key=%s", bucket, key)
    if not key.startswith("reports/") or not key.endswith(".csv"):
        logger.info("report-mailer skipped key=%s", key)
        return {"skipped": key, "trigger": "s3"}
    response = boto3.client("s3").get_object(Bucket=bucket, Key=key)
    try:
        payload = response["Body"].read()
    finally:
        response["Body"].close()
    recipients = [item.strip() for item in os.environ["RECIPIENTS"].split(",") if item.strip()]
    sender = os.environ["SENDER"]
    boto3.client("sesv2").send_email(
        FromEmailAddress=sender,
        Destination={"ToAddresses": recipients},
        Content={"Raw": {"Data": build_raw_message(sender, recipients, key, payload)}},
    )
    logger.info("report-mailer sent trigger=s3 key=%s to=%s", key, ",".join(recipients))
    return {"sent": key, "trigger": "s3"}
