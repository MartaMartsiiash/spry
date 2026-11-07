# Lab 8 — що саме здати і які скріни

Нижче — практичний список під Moodle. Якщо на курсі окремі assignment’и на Part 2 / 3 / 4 — грузити пакетами; якщо один — один zip + PDF/MD з відповідями.

---

## Що здати (файли)

| Що | Файл / папка | Навіщо |
|----|----------------|--------|
| Відповіді Part 2 | `docs/lab8-part2-answers.md` | числа Athena, Glue, JSON vs Parquet |
| Відповіді Part 3 | `docs/lab8-part3-answers.md` | експерименти 1–4 + SUMMARY |
| Відповіді Part 4 | `docs/lab8-part4-answers.md` | діаграма, Athena stream, порівняння з Part 3 |
| Логи експериментів | `lab8/experiments/*.txt` | доказ прогонів consumer/producer |
| Код Part 3 | `lab8/streaming/` | compose + producer + consumer |
| Код Part 4 | `lab8/part4/` | lambda, producer, SQL |
| SQL Part 2 | `lab8/athena/*.sql` | за бажанням / якщо просять код |
| Скріни | окремий zip або папка `screenshots/lab8/` | доказ у консолях |

У відповідях Part 2 вже є примітка: course bucket Access Denied → свій synthetic S3.  
У Part 4 обов’язково одна фраза: **Kinesis/Firehose заборонені SCP на Free → SQS+Lambda**.

---

## Part 2 — скріни (Athena / Glue)

Регіон: **eu-north-1**. Database: **`lab8`**.  
Bucket: `successfulsuccess-lab8-payments-378600555796`.

| # | Ім’я файлу (рекомендоване) | Де зняти | Як пізнати, що скрін правильний |
|---|----------------------------|----------|----------------------------------|
| P2-1 | `p2-athena-scale-count.png` | Athena → Query editor | SQL з `COUNT(*)` / scale; у Results видно **~3 007 000** |
| P2-2 | `p2-athena-view-or-dedup.png` | Athena | створення/select з view `payments` або dedup (`row_number`) + кілька рядків результату |
| P2-3 | `p2-athena-turnover.png` | Athena | turnover по merchant; є Rozetka / Silpo / Nova Poshta, turnover ~80M |
| P2-4 | `p2-athena-failure-rate.png` | Athena | failure rate по method×device; ~7–8% |
| P2-5 | `p2-athena-peak-hours.png` | Athena | payments per hour |
| P2-6 | `p2-athena-late.png` | Athena | late > 60s; число **~60 465** |
| P2-7 | `p2-athena-parquet-stats.png` | Athena Recent queries **або** два скріни JSON vs Parquet | видно **Data scanned**: JSON ~1.1 GB vs Parquet MB |
| P2-8 | `p2-s3-payments-prefix.png` | S3 → bucket → `payments/` | папки `dt=2026-10-01` … `dt=2026-10-31` |
| P2-9 | `p2-glue-crawler.png` | Glue → Crawlers → `successfulsuccess-lab8-payments` | Status Ready/Succeeded |
| P2-10 | `p2-glue-table-schema.png` | Glue → Tables → `crawled_payments` (db `lab8_crawler`) | колонки + **Partition keys: dt** |

Якщо Part 2 уже зданий — ці скріни можна не дублювати.

---

## Part 3 — скріни (Redpanda)

Передумова: `cd lab8/streaming && docker compose up -d`.  
Console: **http://localhost:8080**

| # | Ім’я файлу | Де зняти | Як пізнати |
|---|------------|----------|------------|
| P3-1 | `p3-redpanda-console-topic.png` | Console → Topics → **`payments`** | topic існує; partitions **1 або 3**; є message count / throughput |
| P3-2 | `p3-redpanda-messages.png` | Topic → Messages | JSON з `invoiceId`, `status`, `paymentMethod`, `modifiedDate` |
| P3-3 | `p3-baseline-summary.png` | термінал з `exp0_consumer.txt` або живий consumer | рядок **`SUMMARY … events=6000 …`** |
| P3-4 | `p3-exp1-stop-resume.png` | два термінали / два хвости логів | part1 `events=2000`, part2 `events=4000` (сума 6000) |
| P3-5 | `p3-exp2-two-consumers.png` | два вікна з `exp2_c1.txt` / `exp2_c2.txt` | різні `assigned_partitions=`; сума events = 6000 |
| P3-6 | `p3-exp3-alerts.png` | `exp3_consumer.txt` | багато рядків **`*** ALERT: failures > 10% ***`**; SUMMARY `alerts=279` |
| P3-7 | `p3-exp4-grace.png` | два SUMMARY поруч | grace0: `rejected_late_total=181`; grace120: `rejected_late_total=0` |

Мінімум, якщо ліміт скрінів: **P3-1, P3-5, P3-6, P3-7** + текст з `lab8-part3-answers.md`.

---

## Part 4 — скріни (cloud stream)

Консоль AWS, регіон **Europe (Stockholm) eu-north-1**.

| # | Ім’я файлу | Де зняти | Як пізнати |
|---|------------|----------|------------|
| P4-1 | `p4-architecture.png` | з `docs/lab8-part4-answers.md` (або draw.io) | ланцюг **Producer → SQS → Lambda → S3 → Athena** + гілка **SNS**; підпис що це заміна Kinesis/Firehose |
| P4-2 | `p4-sqs-queue.png` | SQS → **`lab8-payments-stream`** | ім’я черги видно; Standard queue |
| P4-3 | `p4-lambda-config.png` | Lambda → **`lab8-payments-stream-processor`** → Configuration | Trigger **SQS**; env `BUCKET`, `TOPIC_ARN`, `ALERT_THRESHOLD` |
| P4-4 | `p4-lambda-monitor.png` | Lambda → Monitor | є Invocations (після прогону); Errors ≈ 0 |
| P4-5 | `p4-s3-stream-raw.png` | S3 → bucket → **`stream/raw/`** → `dt=2026-11-01/hour=…` | багато `batch-….jsonl` |
| P4-6 | `p4-athena-stream-counts.png` | Athena, db `lab8`, таблиця **`payments_stream`** | `events` ~2510, `failure_pct` ~11.95 |
| P4-7 | `p4-athena-stream-by-method.png` | Athena | monobank/google_pay/card/apple_pay з rate **> 0.10** |
| P4-8 | `p4-sns-topic.png` | SNS → **`lab8-payment-alerts`** **або** CloudWatch metric `NumberOfMessagesPublished` | topic існує / були publish |

Мінімум: **P4-1, P4-3, P4-5, P4-6** + compare-таблиця з answers.

SQL для швидкого повторного скріна Athena:

```sql
-- 02
SELECT COUNT(*) AS events,
       COUNT(DISTINCT invoiceId) AS invoices,
       SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) AS failures,
       ROUND(100.0 * SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_pct
FROM lab8.payments_stream;

-- 03
SELECT paymentMethod, COUNT(*) n,
       SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) failures,
       ROUND(1.0 * SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) / COUNT(*), 4) failure_rate
FROM lab8.payments_stream
GROUP BY paymentMethod
ORDER BY failure_rate DESC;
```

---

## Як зібрати zip (приклад)

```text
lab8-moodle/
  answers/
    lab8-part2-answers.md
    lab8-part3-answers.md
    lab8-part4-answers.md
  experiments/          # скопійовані exp*.txt
  code-streaming/       # docker-compose, producer, consumer
  code-part4/           # lambda + sql
  screenshots/
    p2-...
    p3-...
    p4-...
```

Назви скрінів краще з префіксом `p2-` / `p3-` / `p4-`, щоб перевіряючий одразу бачив частину лаби.

---

## Швидкий чеклист «чи вистачить»

- [ ] Є письмові відповіді на Part 2 + 3 + 4  
- [ ] Є доказ batch lake (Athena/Glue/S3) — Part 2  
- [ ] Є доказ local stream + 4 експерименти — Part 3  
- [ ] Є доказ cloud pipeline + Athena по stream + порівняння з Part 3 — Part 4  
- [ ] Пояснено Access Denied на course bucket і SCP block на Kinesis/Firehose  

Після прийняття роботи можна чистити AWS (команди в кінці `lab8-part4-answers.md`) і `docker compose down`.
