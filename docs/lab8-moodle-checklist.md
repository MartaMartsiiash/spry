# Lab 8 — Moodle upload checklist

## Part 2 (Athena / Glue) — already done

- [ ] `docs/lab8-part2-answers.md`
- [ ] Screenshots: Athena editor + results for queries 2–7, Glue crawler, Parquet compare
- [ ] Zip: `lab8-part2-screenshots/` (if required)

## Part 3 (Redpanda)

- [ ] `docs/lab8-part3-answers.md`
- [ ] Logs: `lab8/experiments/exp*.txt` (or paste SUMMARY tables)
- [ ] Screenshots: Redpanda Console topic `payments`; consumer alert lines; exp2 two consumers / partitions
- [ ] Code: `lab8/streaming/` (`docker-compose.yml`, `producer.py`, `consumer.py`)

## Part 4 (cloud stream)

- [ ] `docs/lab8-part4-answers.md` (diagram + compare table + Athena numbers)
- [ ] Screenshots: Lambda+SQS, S3 `stream/raw/`, Athena `payments_stream` results, SNS/metrics
- [ ] Note in text: Kinesis/Firehose SCP-denied on Free → SQS equivalent

## Optional cleanup

See cleanup commands at the bottom of `docs/lab8-part4-answers.md`. Redpanda: `cd lab8/streaming && docker compose down`.
