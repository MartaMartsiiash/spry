# Lab 8 Part 2 — Athena / Glue answers

**Note:** Course bucket `s3://ucu-ooad-lab8-payments/` returned **Access Denied** from this Free project (`378600555796`).  
We generated an equivalent JSONL dataset (~3.007M events, ~1.15 GB, partitions `dt=2026-10-01`…`2026-10-31`, ~1% exact duplicates, ~2% late by 1–10 minutes) and stored it in:

`s3://successfulsuccess-lab8-payments-378600555796/payments/` (region **eu-north-1**).

Athena database: `lab8`. SQL files: `lab8/athena/*.sql`.

## Scale

| Metric | Value |
|--------|------:|
| Events (`COUNT(*)`) | **3 007 000** |
| Unique `invoiceId` | **992 445** |
| Exact duplicate extra rows | **29 693** (~1.0% of events) |
| Events late **> 1 hour** | **0** (synthetic late window is 1–10 min only) |
| Events late **> 60 s** (query 6) | **60 465** (~2.0%) |

## Query results (2–6)

### 2 — View `lab8.payments`

`DISTINCT *` then `row_number() … PARTITION BY invoiceId ORDER BY modifiedDate DESC` keeping `rn = 1`.

### 3 — Turnover by merchant / currency (success only, whole units)

| merchantId | merchantName | ccy | success_payments | turnover (approx) |
|------------|--------------|-----|------------------:|------------------:|
| m_004 | Nova Poshta | 980 | 114414 | 81 600 790 |
| m_001 | Rozetka | 980 | 114535 | 81 454 125 |
| m_002 | Silpo | 980 | 114274 | 81 300 164 |
| … | … | 980 | ~114k each | ~80–81M |

(Full preview: `lab8/athena/03_turnover.preview.txt`.)

### 4 — Failure rate by paymentMethod × device

Highest ~**8.13%** (`apple_pay` / `android`); others ~7.9–8.1%.  
(Full: `04_failure_rate.preview.txt`.)

### 5 — Payments per hour

Roughly flat ~41k payments/hour (synthetic uniform hours).  
(Full: `05_peak_hours.preview.txt`.)

### 6 — Late > 60 s

**60 465** events.

## JSON vs Parquet (queries 3–5) — Data scanned & time

| Query | JSON scanned | JSON engine ms | Parquet scanned | Parquet engine ms | ≈ cheaper (scan) |
|-------|-------------:|---------------:|----------------:|------------------:|-----------------:|
| 3 Turnover | 1 149.7 MB | 3674 | 1.5 MB | 873 | **~780×** |
| 4 Failure rate | 1 149.7 MB | 4147 | 0.7 MB | 724 | **~1696×** |
| 5 Peak hours | 1 149.7 MB | 3687 | 6.5 MB | 1150 | **~177×** |

Parquet table: `lab8.payments_parquet` via CTAS → `s3://…/curated/payments/`.

Athena bills by data scanned → Parquet is **orders of magnitude** cheaper here because columnar projection + compression; JSON SerDe reads whole objects.

## Why `DISTINCT` before `row_number()`?

- Exact duplicate lines (same payload twice) must not become two “latest” candidates.  
- `DISTINCT` collapses identical rows first; then `row_number()` picks the newest status per `invoiceId`.  
- Without dedup: inflated counts, wrong turnover (`SUM` double-counts), wrong failure rates, and unstable “latest” if duplicates share `modifiedDate`.

## Way B — Glue Crawler

Crawler: `successfulsuccess-lab8-payments` → database `lab8_crawler`, table `crawled_payments`.

| Question | Answer |
|----------|--------|
| Types for `amount`, `ccy`, dates? | `amount`/`finalamount` → **int**; `ccy` → **int**; dates → **string** (ISO text, not timestamp) |
| Did it recognise `dt` as partition? | **Yes** (`PartitionKeys: dt string`) |
| What about `failureReason`? | Present as **string** (`failurereason`); nulls on non-failure events are fine — Glue still adds the column from samples that have it |
| Which schema is more convenient? | **Hand-written** for analytics: stable camelCase names, `bigint` for money, explicit nullability/docs. Crawlers lowercase names, may pick `int` vs `bigint`, and sample-based `recordCount` can be wrong. Hand schemas stay common for contracts, CI, and reproducible Athena SQL. |

## Console links (for screenshots)

- Athena (eu-north-1): reopen saved queries or re-run SQL from `lab8/athena/`  
- S3 data: `s3://successfulsuccess-lab8-payments-378600555796/payments/`  
- Glue: Crawlers → `successfulsuccess-lab8-payments` → table `crawled_payments`
