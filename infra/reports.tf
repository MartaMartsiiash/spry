# Was infra/reports.yml (Lab 5). Weekly report: SQS → builder → S3 → mailer.
# Aurora Express: builder has no VPC (matches live stack).

# --- bucket (notifications are a separate resource; no CFN circular DependsOn) ---

resource "aws_s3_bucket" "reports" {
  bucket = local.reports_bucket_name
  # Match imported bucket (force_destroy was false under CFN).
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "expire-reports"
    status = "Enabled"

    filter {
      prefix = "reports/"
    }

    expiration {
      days = 90
    }
  }

  rule {
    id     = "expire-requests"
    status = "Enabled"

    filter {
      prefix = "requests/"
    }

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_policy" "reports" {
  bucket = aws_s3_bucket.reports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.reports.arn,
        "${aws_s3_bucket.reports.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

# --- queues ---

resource "aws_sqs_queue" "report_dlq" {
  name                      = "${var.project_name}-report-requests-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "report_queue" {
  name                       = "${var.project_name}-report-requests"
  visibility_timeout_seconds = 360
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.report_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_policy" "report_dlq" {
  queue_url = aws_sqs_queue.report_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSourceQueue"
      Effect    = "Allow"
      Principal = { Service = "sqs.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.report_dlq.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sqs_queue.report_queue.arn }
      }
    }]
  })
}

# --- builder ---

resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/lambda/${var.project_name}-report-builder"
  retention_in_days = 7
}

resource "aws_iam_role" "builder" {
  name = "successfulsuccess-reports-BuilderRole-mn9IZsJ9J3Dc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "builder_basic" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "builder" {
  name = "build-report"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility",
        ]
        Resource = aws_sqs_queue.report_queue.arn
      },
    ]
  })
}

resource "aws_lambda_function" "builder" {
  function_name = "${var.project_name}-report-builder"
  description   = "Builds one weekly meetings CSV from Aurora and stores it in S3."
  role          = aws_iam_role.builder.arn
  package_type  = "Image"
  image_uri     = var.reports_image_uri
  architectures = [var.builder_architecture]
  memory_size   = 512
  timeout       = 60

  image_config {
    command = ["app.reports.lambda_handler.handler"]
  }

  environment {
    variables = {
      DATABASE_URL      = var.database_url
      DATABASE_IAM_AUTH = var.database_iam_auth
      APP_TIMEZONE      = var.app_timezone
      REPORTS_BUCKET    = aws_s3_bucket.reports.bucket
      REPORT_FAIL_WEEK  = var.report_fail_week
      LOG_LEVEL         = "INFO"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.builder,
    aws_iam_role_policy.builder,
  ]
}

resource "aws_lambda_event_source_mapping" "builder" {
  event_source_arn = aws_sqs_queue.report_queue.arn
  function_name    = aws_lambda_function.builder.arn
  batch_size       = 1
  enabled          = true
}

# --- schedule ---

resource "aws_iam_role" "scheduler" {
  name = "successfulsuccess-reports-SchedulerRole-pyluD8lZpZXK"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "send-report-command"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.report_queue.arn
    }]
  })
}

resource "aws_scheduler_schedule" "weekly" {
  name                         = "${var.project_name}-weekly-report"
  description                  = "Monday 07:00 in the app timezone."
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.app_timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.report_queue.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ week = null, source = "schedule" })
  }
}

# --- mailer (inline zip, re-created on apply if needed) ---

data "archive_file" "mailer" {
  type        = "zip"
  output_path = "${path.module}/.build/mailer.zip"

  source {
    filename = "index.py"
    content  = <<-PY
      """Email the CSV that S3 just saved. Never writes back under reports/."""
      import logging
      import os
      from email.message import EmailMessage
      from urllib.parse import unquote_plus
      import boto3
      logger = logging.getLogger()
      logger.setLevel(logging.INFO)

      def build_raw_message(sender, recipients, key, payload):
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
          recipients = [i.strip() for i in os.environ["RECIPIENTS"].split(",") if i.strip()]
          sender = os.environ["SENDER"]
          boto3.client("sesv2").send_email(
              FromEmailAddress=sender,
              Destination={"ToAddresses": recipients},
              Content={"Raw": {"Data": build_raw_message(sender, recipients, key, payload)}},
          )
          logger.info("report-mailer sent trigger=s3 key=%s to=%s", key, ",".join(recipients))
          return {"sent": key, "trigger": "s3"}
    PY
  }
}

resource "aws_cloudwatch_log_group" "mailer" {
  name              = "/aws/lambda/${var.project_name}-report-mailer"
  retention_in_days = 7
}

resource "aws_iam_role" "mailer" {
  name = "successfulsuccess-reports-MailerRole-oUJDd36JyF60"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mailer_basic" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer" {
  name = "send-report"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      {
        Effect = "Allow"
        Action = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = local.has_domain ? [
          "arn:aws:ses:${var.region}:${local.account_id}:identity/${var.sender_domain}",
          "arn:aws:ses:${var.region}:${local.account_id}:identity/${var.recipient_email}",
          ] : [
          "arn:aws:ses:${var.region}:${local.account_id}:identity/${var.recipient_email}",
        ]
      },
    ]
  })
}

resource "aws_lambda_function" "mailer" {
  function_name = "${var.project_name}-report-mailer"
  description   = "Sends the weekly CSV. Not in a VPC, so it can reach SES."
  role          = aws_iam_role.mailer.arn
  filename      = data.archive_file.mailer.output_path
  source_code_hash = data.archive_file.mailer.output_base64sha256
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  environment {
    variables = {
      SENDER     = local.sender_address
      RECIPIENTS = var.recipient_email
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.mailer,
    aws_iam_role_policy.mailer,
  ]
}

resource "aws_lambda_permission" "mailer_s3" {
  statement_id  = "AllowS3Mailer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mailer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.reports.arn
  source_account = local.account_id
}

# --- enqueue ---

data "archive_file" "enqueue" {
  type        = "zip"
  output_path = "${path.module}/.build/enqueue.zip"

  source {
    filename = "index.py"
    content  = <<-PY
      """Turn a request file into the same SQS command the schedule sends."""
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
    PY
  }
}

resource "aws_cloudwatch_log_group" "enqueue" {
  name              = "/aws/lambda/${var.project_name}-report-enqueue"
  retention_in_days = 7
}

resource "aws_iam_role" "enqueue" {
  name = "successfulsuccess-reports-EnqueueRole-oiJ7KQ5VY4FJ"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "enqueue_basic" {
  role       = aws_iam_role.enqueue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "enqueue" {
  name = "enqueue-report"
  role = aws_iam_role.enqueue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.reports.arn}/requests/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.report_queue.arn
      },
    ]
  })
}

resource "aws_lambda_function" "enqueue" {
  function_name = "${var.project_name}-report-enqueue"
  description   = "Reads requests/*.json and sends the SQS command. Not in a VPC."
  role          = aws_iam_role.enqueue.arn
  filename      = data.archive_file.enqueue.output_path
  source_code_hash = data.archive_file.enqueue.output_base64sha256
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.report_queue.url
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.enqueue,
    aws_iam_role_policy.enqueue,
  ]
}

resource "aws_lambda_permission" "enqueue_s3" {
  statement_id   = "AllowS3Enqueue"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.enqueue.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.reports.arn
  source_account = local.account_id
}

resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.enqueue.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "requests/"
    filter_suffix       = ".json"
  }

  depends_on = [
    aws_lambda_permission.mailer_s3,
    aws_lambda_permission.enqueue_s3,
  ]
}

# --- SES + DLQ alarm ---

resource "aws_sesv2_email_identity" "recipient" {
  email_identity = var.recipient_email
}

resource "aws_sns_topic" "dlq_alarm" {
  name = "${var.project_name}-report-dlq"
}

resource "aws_sns_topic_policy" "dlq_alarm" {
  arn = aws_sns_topic.dlq_alarm.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudWatch"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.dlq_alarm.arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "dlq_alarm_email" {
  topic_arn = aws_sns_topic.dlq_alarm.arn
  protocol  = "email"
  endpoint  = var.recipient_email
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${var.project_name}-report-dlq-not-empty"
  alarm_description   = "A weekly report exhausted its three attempts and is waiting in the dead-letter queue."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.dlq_alarm.arn]

  dimensions = {
    QueueName = aws_sqs_queue.report_dlq.name
  }
}
