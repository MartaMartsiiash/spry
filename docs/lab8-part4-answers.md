![alt text](image.png)# Lab 8 Part 4 — Cloud streaming + Athena

## Constraint (Free project)

`kinesis:*` and `firehose:*` are **explicitly denied by SCP** on this Free AWS project (`378600555796`, region `eu-north-1`).

Equivalent pipeline used instead:

**Producer → Amazon SQS → Lambda → S3 (JSONL) → Athena**, with **SNS** alerts when a batch’s failure share for a method is **> 10%**.

Same roles as the classic Kinesis→Firehose design: buffer, serverless processor, durable lake, SQL, alerts.

## Architecture

```text
  payments JSONL                 lab8-payments-stream
  (sqs_producer.py)  ------->   Amazon SQS
                                    |
                                    | event source mapping (batch 50)
                                    v
                         Lambda lab8-payments-stream-processor
                           |                        |
                           | put Object             | Publish if fail_rate > 10%
                           v                        v
              s3://…/stream/raw/dt=…/hour=…/    SNS lab8-payment-alerts
                           |
                           v
                    Athena lab8.payments_stream
```

Code / SQL: `lab8/part4/`.

| Resource | Name / ARN tip |
|----------|----------------|
| Queue | `lab8-payments-stream` |
| Lambda | `lab8-payments-stream-processor` |
| SNS | `lab8-payment-alerts` (~139 publishes in the test window) |
| S3 prefix | `s3://successfulsuccess-lab8-payments-378600555796/stream/raw/` |
| Athena table | `lab8.payments_stream` |

## Run results

Produced **2500** events with `--fail-boost 0.30`. Lambda wrote **~71** JSONL batches; **2510** lines landed in S3 (includes earlier probe).

Athena `02_stream_counts.sql`:

| events | invoices | failures | failure_pct |
|-------:|---------:|---------:|------------:|
| 2510 | 2440 | 300 | **11.95%** |

Athena `03_stream_by_method.sql` (all methods > 10% → alerts expected):

| paymentMethod | n | failures | failure_rate |
|---------------|--:|---------:|-------------:|
| monobank | 598 | 80 | 0.1338 |
| google_pay | 621 | 74 | 0.1192 |
| card | 632 | 72 | 0.1139 |
| apple_pay | 659 | 74 | 0.1123 |

## Compare Part 3 (Redpanda) vs Part 4 (SQS/Lambda)

| | Part 3 Redpanda | Part 4 SQS + Lambda |
|--|-----------------|---------------------|
| API | Kafka (partitions, consumer groups) | SQS competing consumers |
| Ordering | Per partition | Best-effort per queue |
| Windowing | Event-time + watermark in long-lived consumer | Per-invocation batch stats (+ SNS) |
| Durability / replay | Topic retention, offset seek | SQS retention; lake replay via S3/Athena |
| Ops | Docker local | Fully managed, scales with load |
| Cost / Free tier | Free local | SQS/Lambda/S3/Athena available; Kinesis/Firehose blocked by SCP |

**Takeaway:** local Kafka/Redpanda is better for exact event-time window experiments and replay. Cloud path is better for durable lake landing + SQL (Athena) and managed alerting; with Kinesis available you’d swap SQS→Kinesis and Lambda/S3 landing→Firehose with almost the same diagram.

## Screenshots to capture for Moodle

1. Architecture diagram (this file or redraw)
2. Lambda function + SQS trigger in console
3. S3 `stream/raw/…` objects
4. Athena query results (counts + by method)
5. Optional: SNS topic / CloudWatch `NumberOfMessagesPublished`

## Cleanup (optional, saves spend)

```bash
source lab8/part4/env.sh
aws lambda delete-event-source-mapping --uuid "$ESM" --region $REGION
aws lambda delete-function --function-name lab8-payments-stream-processor --region $REGION
aws sqs delete-queue --queue-url "$QUEUE_URL" --region $REGION
aws sns delete-topic --topic-arn "$TOPIC_ARN" --region $REGION
aws iam delete-role-policy --role-name lab8-stream-lambda-role --policy-name lab8-stream-inline
aws iam delete-role --role-name lab8-stream-lambda-role
aws s3 rm "s3://$BUCKET/stream/" --recursive --region $REGION
# keep payments/ + curated/ if still needed for Part 2
```
