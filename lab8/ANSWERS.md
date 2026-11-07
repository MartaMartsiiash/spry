# Lab 8 — Big Data on AWS: the Uklon example

Repository: `MartaMartsiiash/spry`, folder `lab8/` (branch `lab8`).
Region: eu-north-1, bucket `successfulsuccess-lab8-payments-378600555796`.

---

## Part 1 — Uklon's data architecture

**What happens if the real-time road falls behind by 10 minutes? And the batch road by a day?**

- *Real-time 10 min behind* — the product breaks right now. Driver positions in Redis are 10 minutes old, so matching sends drivers who are already elsewhere; surge multipliers in DynamoDB react to a demand spike that is already over (or miss the current one); fraud/failure alerts arrive after the money is gone; "your driver is coming" pushes are wrong. Users feel it within seconds, revenue is lost directly. Kinesis keeps the data (24 h+ retention), so nothing is lost — Flink catches up — but stale decisions made during the lag cannot be undone.
- *Batch 1 day behind* — almost nobody outside the data team notices. Yesterday's dashboards in Quick are missing, the nightly ETA/demand model is trained on data one day older, analysts wait. Rides continue normally. Next night the Glue job processes two days and everything is consistent again, because raw JSON is still in S3.
- Conclusion: the real-time road has a seconds-level SLA and needs monitoring/alerting on lag; the batch road has an hours-level SLA and is cheap to rerun.

**Why does GPS not go through Lambda (API Gateway + Lambda)?**

- Volume: ~580 M pings/day ≈ 6 700 requests/s on average. Per-request pricing (API Gateway ~$1 per million + Lambda invocations/duration) gives roughly $600+/day, i.e. tens of thousands of dollars per month, for tiny 100-byte messages.
- Every ping would be a new HTTPS request: TLS handshake, headers, battery and mobile-data cost on the driver's phone. MQTT keeps one persistent connection per driver and sends a few bytes every 3 s.
- IoT Core is built for millions of long-lived device connections and forwards messages straight into Kinesis; Lambda would add cold starts and concurrency limits for no business logic (a ping only needs to be stored and streamed, not processed individually).

**Which parts would a small startup drop first, and what would it lose?**

| Drop | Replace with | What is lost |
|---|---|---|
| SageMaker | Simple rules / average speed per district for ETA | Accuracy of ETA and demand forecasts |
| Managed Flink + DynamoDB surge | Fixed tariff or a cron job recalculating surge every few minutes | Dynamic pricing in seconds, real-time alerts |
| Glue + Parquet + Athena + Quick | SQL directly on Aurora / a read replica, or a weekly CSV export | Cheap analytics on history without loading production DB |
| DMS (CDC) | Services write events themselves | One unified event stream |
| IoT Core + Kinesis | GPS over the normal API into Redis | Cost-efficient GPS at scale (fine while there are hundreds of drivers, not tens of thousands) |

What stays: ALB, one service on ECS, Aurora, Redis for driver positions, SNS push — the minimum that makes a ride happen. The startup loses scale, automation and data-driven pricing, but saves money and complexity until the volume justifies them.

---

## Part 2 — Batch on AWS: payments in S3

Queries are in `lab8/athena/*.sql`, results in `*.preview.txt`, run statistics (Data scanned, run time) in `*.summary.json`.

### Scale

| Metric | Value |
|---|---|
| Events (`COUNT(*)`) | **3 007 000** |
| Unique `invoiceId` (payments) | **992 445** |
| Exact duplicate rows | **29 693** (≈ 0.99 % of events) |
| Events more than 1 hour late | **0** (lateness is 1–10 min only) |
| Events more than 60 s late (query 6) | **60 465 of 3 007 000** (≈ 2.01 %) |

### Results of queries 2–6

- **2. Deduplication** — view `lab8.payments`: `SELECT DISTINCT *`, then `row_number() OVER (PARTITION BY invoiceId ORDER BY modifiedDate DESC)`, keep `rn = 1`. Result: one row per payment, **992 445 rows** (= number of unique invoiceIds).
- **3. Turnover** (success only, UAH, `finalAmount / 100`): ≈ 80.5–81.6 M UAH per merchant; top is Nova Poshta 81 600 790 UAH (114 414 payments), lowest Uklon Ride 80 544 035 UAH. See `03_turnover.preview.txt`.
- **4. Failure rate** by method and device: 7.90 % (card/ios) … 8.13 % (apple_pay/android). Spread is small — no method/device is clearly worse.
- **5. Peak hours**: 41 009 – 41 746 payments per hour, flat across 24 h (max at 23:00 UTC, min at 21:00 UTC).
- **6. Late events**: 60 465 of 3 007 000 events arrived > 60 s after `modifiedDate` (≈ 2 %).

### JSON vs Parquet (queries 3–5)

| Query | JSON scanned | JSON time | Parquet scanned | Parquet time | Less data |
|---|---|---|---|---|---|
| 3 Turnover | 1 149.7 MB | 3.84 s | 1.47 MB | 1.02 s | **~780×** |
| 4 Failure rate | 1 149.7 MB | 4.31 s | 0.68 MB | 0.89 s | **~1 700×** |
| 5 Peak hours | 1 149.7 MB | 3.83 s | 6.51 MB | 1.31 s | **~176×** |

Athena charges $5 per TB scanned with a 10 MB minimum per query. JSON: 1.15 GB ≈ $0.0057 per query. Parquet: billed as 10 MB ≈ $0.00005. So in money it is **~115× cheaper** per query (the 10 MB minimum caps the gain), and 3–4× faster. Parquet is columnar and compressed: the query reads only the columns it needs (e.g. `status`, `paymentMethod`, `device`) instead of parsing every full JSON line.

### Why DISTINCT comes before row_number(), and what breaks without deduplication

- An exact duplicate is the same event delivered twice (same `modifiedDate`). `row_number()` ordered by `modifiedDate` sees a tie between two identical rows; it still picks one, but `DISTINCT` first makes the result deterministic and reduces the rows the window function has to sort.
- More importantly, the two steps solve different problems: `DISTINCT` removes **delivery duplicates** (webhook retries); `row_number()` collapses **different events of one payment** (created → processing → success/failure) into its final state. If you only used `row_number()`, ties could pick any copy; if you only used `DISTINCT`, every payment would still appear 2–3 times.
- Without deduplication: `COUNT(*)` reports ~3 M "payments" instead of ~1 M; turnover is inflated by every duplicated `success` event (~1 %); failure rate is wrong because `created`/`processing` rows are counted as non-failures; peak hours count events, not payments.

### Way B — Glue Crawler

Crawler `lab8-payments-crawler` over `s3://…/payments/`, target database `lab8`, prefix `crawled_`. Run: **Completed in 37 s, 0.115 DPU-hours (≈ $0.05)**, result "1 table change, 31 partition changes" → table `lab8.crawled_payments`, classification JSON, 17 columns.

| Field | Hand-written (`payment_events`) | Crawler (`crawled_payments`) |
|---|---|---|
| `amount`, `finalAmount` | `bigint` | **`int`** |
| `ccy` | `int` | `int` |
| `createdDate`, `modifiedDate`, `receivedAt` | `string` | `string` (ISO text is not recognised as timestamp) |
| `failureReason` | `string` | `string`, but placed **last** (#16), after fields that every event has |
| column names | camelCase | **all lower-case** (`invoiceid`, `finalamount`, `paymentmethod`) |
| `dt` | partition column | **recognised as partition key** (`Partition (0)`), 31 partitions = 31 days |

- **Types:** the crawler picked `int` for the amounts because the sampled values fit into 32 bits; a bigger payment in a later file would overflow or force a schema change, so for money a hand-written `bigint` (or `decimal`) is safer. Dates stay `string` in both — they are parsed with `from_iso8601_timestamp()` in queries.
- **`failureReason`:** present only on failed events. The crawler merged the schemas of all sampled files and added it as an optional `string` column; rows without it return NULL. It ended up at the end of the column list because it was first seen after the common fields.
- **Which is more convenient:** the crawler is faster to start (no DDL, finds partitions itself, can re-run to pick up new days). Hand-written schemas are still common because they are explicit and stable: exact types (`bigint`, `decimal`, `timestamp`), the original column names, reviewed in git, and they do not change silently when one malformed or unusual file appears; crawlers also cost money per run and can split one dataset into several tables if files differ.

---

## Part 3 — Streaming locally: Redpanda + Python

Code: `lab8/streaming/` (`docker-compose.yml`, `producer.py`, `consumer.py`). Topic `payments`, 3 partitions, key = `invoiceId`. Consumer: drops duplicates, 1-minute **event-time** windows by `modifiedDate`, failure share per `paymentMethod`, alert when > 10 %, window closes 2 minutes (120 s grace) after it ends. Outputs in `lab8/experiments/`.

| Experiment | Events | Windows | Alerts | Duplicates dropped | Rejected as late |
|---|---|---|---|---|---|
| 0 Baseline | 6 000 | 93 | 58 | 61 | 0 |
| 1 Stop/restart consumer | 2 000 + 4 000 = 6 000 | 32 + 62 | 19 + 40 | 19 + 42 | 0 |
| 2 Two consumers, one group | 3 903 (p0, p1) + 2 097 (p2) = 6 000 | 93 each | 79 / 44 | 44 / 17 | 0 |
| 3 Producer fails 30 % | 6 000 | 93 | **279** | 52 | 0 |
| 4a Late events, grace 0 s | 5 200 (200 injected late) | 78 | 45 | 70 | **181** |
| 4b Same, grace 120 s | 5 200 | 78 | 45 | 251 | **0** |

What changed in the numbers:

1. **Stop and restart** — the consumer read 2 000 events, was stopped, and after restart continued from the committed offset with the remaining 4 000. Total 6 000 = baseline: no events lost and none re-read, because Kafka/Redpanda keeps the log and the consumer group stores its offset.
2. **Two consumers in one group** — Redpanda split the 3 partitions: consumer 1 got partitions 0 and 1 (3 903 events), consumer 2 got partition 2 (2 097). Together exactly 6 000. Because the key is `invoiceId`, all events of one payment stay in one partition, so each consumer can deduplicate and pick the latest status on its own.
3. **30 % failures** — alerts rose from 58 to 279 (almost 5×); nearly every window/method now exceeds 10 %. In the baseline some alerts already fire because a 1-minute window has only a few payments per method, so one failure out of 6 is already 16.7 % (small-sample noise).
4. **Grace = 0** — 181 of the 200 injected late events were rejected because their window had already closed; windows are counted without them, so failure shares are slightly wrong. With grace 120 s none were rejected: they reached their open window (and since they were re-sends, the dedup counted them as duplicates: 251 vs 70). Trade-off: longer grace = more correct numbers, but alerts come 2 minutes later and more state is kept in memory.

The set of already seen events grows without limit; in production it lives in Redis or in Flink state with a TTL (e.g. a bit longer than the maximum lateness), so old keys expire.

---

## Part 4 — Streaming in the cloud

Diagram: `lab8/part4/pipeline.png`. Code: `lab8/part4/sqs_producer.py` / `sqs_producer.sh` (producer), `lambda_function.py` (consumer), `01–03_*.sql` (Athena).

**Data source:** the same payments dataset (one day, `dt=2026-10-01`), 2 500 events sent in batches of 10, with 30 % of payments forced to `failure` to test the alert.

**Pipeline:** Producer (Python, laptop) → **Amazon SQS** queue `lab8-payments-stream` → **Lambda** `lab8-payments-stream-processor` (event source mapping; dedup inside the batch, writes the batch as JSON Lines to `s3://…/stream/raw/dt=…/hour=…/`, computes failure share per payment method and publishes an alert to the **SNS** topic `lab8-payment-alerts` when > 10 %) → **S3** → **Athena** table `lab8.payments_stream`.

**Athena result over the data that came through the stream:** 2 510 events, 2 440 invoices, 300 failures (11.95 %). By method: monobank 13.38 %, google_pay 11.92 %, card 11.39 %, apple_pay 11.23 % — all above 10 %, so the Lambda published alerts to the SNS topic (see `athena_by_method.json`). The topic has no email subscription yet, so the alerts were published but not delivered to an inbox; adding an email subscription is the only step left to receive them.

**Difference from the diagram:** Kinesis Data Streams and Data Firehose are blocked on this AWS account by an organization Service Control Policy (SCP), so the stream is replaced with SQS + Lambda: SQS buffers the events like the stream, and Lambda both writes the S3 files (Firehose's job) and checks the failure rate. The table over the stream data was created in Athena by hand (same Glue Data Catalog).

**How it differs from local Redpanda:**
- Redpanda is a log: messages stay after reading, several consumer groups can re-read from any offset (Experiment 1). SQS is a queue: a message is deleted after Lambda processes it; there is no replay and no partitions/ordering by key (standard queue). Kinesis would keep a 24 h log and shard by key like Redpanda.
- Locally the consumer runs event-time windows with a 2-min grace period; in the cloud each Lambda invocation sees only one batch (≤ 10 messages), so the failure check is per batch, not per event-time window — real windows would need Managed Flink or state in DynamoDB.
- Nothing to install or keep running: AWS scales Lambda, stores data in S3 and lets you query it with SQL; locally we had to run Docker and restart processes by hand.

**Cost:** SQS — first 1 M requests/month free (we used ~250 batch requests); Lambda — free tier (1 M invocations, 400 000 GB-s); S3 — a few hundred KB; Athena — ~10 MB minimum per query ≈ $0.00005; SNS — first 1 M publishes free. Total ≈ **$0.00**. For comparison, a Kinesis on-demand stream costs ≈ $0.04 per stream-hour plus per-GB charges, Firehose ≈ $0.029/GB, so it must be deleted after the lab.

---

## What we discuss in class

- **Event time vs processing time.** Our windows use event time (`modifiedDate`). A late event (arrived after its window + grace) is rejected and counted (`rejected_late`); within the grace it is put into its correct window.
- **Why raw JSON and Parquet both.** Raw JSON is the immutable source of truth (can rebuild everything if the ETL had a bug, schema changes); Parquet is the curated, deduplicated, columnar copy for cheap and fast queries (176–1 700× less data scanned).
- **Nightly batch vs seconds.** Batch is enough for reports, accounting, model training, monthly turnover. Seconds are needed when a decision is made now: matching, surge pricing, fraud and failure alerts.
- **Managed vs self-hosted.** Kinesis/Flink/Glue give scaling, replication, patching, monitoring and pay-per-use with zero servers; you pay a premium per GB/hour and accept less control and vendor lock-in. Running Kafka and Spark yourself is cheaper at large constant volume but needs a team to operate it.
