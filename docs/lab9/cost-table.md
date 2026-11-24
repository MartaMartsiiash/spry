# Lab 9, Part 3 — Spry's core on AWS and on Google Cloud: what it costs

On-demand list prices in USD, without tax, 730 hours a month. AWS in us-east-1 (as in Lab 4),
Google Cloud in us-central1 / europe-west1 (same Tier 1 prices). Services as chosen in
[ADR 0008](../adr/0008-spry-on-google-cloud.md): Cloud SQL `db-f1-micro`, Cloud Run, Firebase
Hosting.

## Assumptions

- **Free tiers** used: CloudFront Free plan (WAF included), Lambda 1M requests + 400,000 GB-s,
  Firebase Hosting free plan (10 GB stored, 360 MB/day out), Cloud Run 2M requests + 180,000
  vCPU-s + 360,000 GiB-s, Artifact Registry 0.5 GB, Secret Manager 6 versions. Registry, secrets and
  logs stay inside the free tier or cost a few cents.
- **Aurora Serverless v2** wakes at 0.5 ACU ($0.12 per ACU-hour → $0.06/h) and pauses when idle;
  storage ~1 GB at $0.10/GB.
- **Cloud SQL `db-f1-micro`**: $0.0105/h while running; 10 GB SSD at $0.17/GB = $1.70, billed even
  while stopped. Two options: left running (default) or stopped outside the hours of use.
- **Busy around the clock** = ~1 request/s on average, 200 ms each, 512 MB:
  2.6M requests a month, ~526,000 vCPU-s, ~263,000 GiB-s.

## Reference: nobody using it for a month

| Piece | AWS | Google Cloud |
|---|---|---|
| Frontend + CDN + HTTPS | CloudFront Free plan → $0 | Firebase Hosting free → $0 |
| API | Lambda, idle → $0 | Cloud Run, scaled to zero → $0 |
| Database compute | Aurora, paused → $0 | Cloud SQL running → $7.67 |
| Database storage | ~1 GB → $0.10 | 10 GB SSD → $1.70 |
| Registry, secrets, logs | a few cents | free tier |
| **Total** | **≈ $0.30** | **≈ $9.40** (≈ $1.70 stopped) |

## The four traffic profiles from Lab 4

| Profile | Hours the DB is awake | AWS: Aurora + rest | GCP: Cloud SQL left running | GCP: Cloud SQL stopped when unused | Cheaper |
|---|---|---|---|---|---|
| Nobody | 0 | $0 + $0.30 = **≈ $0.30** | **≈ $9.40** | **≈ $1.70** | AWS |
| Class demos (10 × 2 h) | 20 | 20 × $0.06 = $1.20 + $0.30 = **≈ $1.50** | **≈ $9.40** | $0.21 + $1.70 = **≈ $1.90** | AWS (GCP close if stopped) |
| Office hours (8 h × 22 days) | 176 | 176 × $0.06 = $10.56 + $0.30 = **≈ $10.90** | **≈ $9.40** | $1.85 + $1.70 = **≈ $3.55** | GCP |
| Busy around the clock | 730 | 730 × $0.06 = $43.80 + $0.30 + Lambda $0.32 = **≈ $44.40** | $9.40 + Cloud Run $8.55 = **≈ $17.90** | (cannot stop) **≈ $17.90** | GCP |

Compute for the busy profile:

- **Lambda:** 2.6M − 1M free = 1.6M × $0.20/M = $0.32; 263,000 GB-s < 400,000 free → $0.
- **Cloud Run:** 2.6M − 2M free = 0.6M × $0.40/M = $0.24; (526,000 − 180,000) vCPU-s ×
  $0.000024 = $8.30; 263,000 GiB-s < 360,000 free → $0. Total ≈ $8.55.

## Answers

**Which cloud is cheaper for each profile, and which single line decides it?**
AWS is cheaper when the app is idle or used rarely (nobody, class demos): Aurora pauses to $0,
Cloud SQL keeps billing. GCP is cheaper for office hours and around the clock: an always-on
`db-f1-micro` ($0.0105/h) is about six times cheaper per hour than an awake Aurora at 0.5 ACU
($0.06/h). **The deciding line is always database compute.** Frontend, API, registry and secrets
are $0 or cents on both clouds.

**Lab 4 showed that Aurora can become more expensive than an instance when something keeps it
awake. Where is the equivalent trap on the GCP side?**
On GCP the trap is the opposite: **Cloud SQL never pauses**, so a forgotten instance bills every
hour even with zero users, and a *stopped* one still bills its disk. Two more traps of the same
kind: Cloud Run with **minimum instances ≥ 1** or **instance-based billing** ("CPU always
allocated") bills around the clock like a VM even with no requests; and if the database is moved to
**Firestore**, the bill follows the code: a list page that reads 500 documents per visit spends the
50,000 free daily reads after 100 visits.

*Check:* the same figures can be reproduced in the
[Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) (Cloud SQL for
PostgreSQL, Enterprise, shared core `db-f1-micro`, 10 GB SSD; Cloud Run, request-based) and the
[AWS Pricing Calculator](https://calculator.aws/) (Aurora PostgreSQL Serverless v2, 0.5 ACU). Both
work without an account.
