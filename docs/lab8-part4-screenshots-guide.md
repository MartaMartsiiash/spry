# Part 4 — детально: куди заходити і що має бути видно на скрінах

**Регіон AWS завжди:** Europe (Stockholm) **`eu-north-1`**  
(у шапці Console справа вгорі перевір, що не us-east-1).

**Важливо в тексті здачі:** Kinesis/Firehose на Free project **заборонені SCP**, тому пайплайн =  
**SQS → Lambda → S3 → Athena** + **SNS** alerts.

Прямі імена ресурсів:

| Ресурс | Ім’я |
|--------|------|
| SQS | `lab8-payments-stream` |
| Lambda | `lab8-payments-stream-processor` |
| SNS | `lab8-payment-alerts` |
| S3 bucket | `successfulsuccess-lab8-payments-378600555796` |
| S3 prefix | `stream/raw/` |
| Athena DB / table | `lab8` / `payments_stream` |

Увійти: [https://console.aws.amazon.com/](https://console.aws.amazon.com/) (твій Free project).

---

## Скрін P4-1 — Архітектурна діаграма

### Куди

Не AWS. Відкрий `docs/lab8-part4-answers.md` (секція Architecture) **або** намалюй у draw.io / Excalidraw / Notion і зроби скрін.

### Що має бути видно

Ланцюг зліва направо:

1. Producer (`sqs_producer.py`)  
2. → **SQS** `lab8-payments-stream`  
3. → **Lambda** `lab8-payments-stream-processor`  
4. → **S3** `…/stream/raw/`  
5. → **Athena** `lab8.payments_stream`  
6. Окрема стрілка з Lambda → **SNS** `lab8-payment-alerts` (alerts >10% failures)

Підпис на діаграмі або під скріном:  
*«Kinesis/Firehose SCP-denied → SQS equivalent»*.

---

## Скрін P4-2 — Черга SQS

### Куди (клік за кліком)

1. AWS Console → пошук **SQS** (або Services → Simple Queue Service)  
2. Ліворуч **Queues**  
3. У списку клікни **`lab8-payments-stream`**

### Що має бути видно

- Ім’я черги: **`lab8-payments-stream`**
- Type: **Standard**
- Region у URL/шапці: **eu-north-1**
- ARN виду `arn:aws:sqs:eu-north-1:378600555796:lab8-payments-stream`

Добре (не обов’язково): вкладка Details з Approximate number of messages (після прогону може бути 0 — це нормально, Lambda уже вичитала).

---

## Скрін P4-3 — Lambda + SQS trigger

### Куди

1. Services → **Lambda** → **Functions**  
2. Кликни **`lab8-payments-stream-processor`**  
3. Вкладка **Configuration**  
4. Ліворуч **Triggers** (і за бажанням окремий скрін **Environment variables**)

### Що має бути видно на Triggers

- Trigger: **SQS**
- Queue: **`lab8-payments-stream`** (або ARN цієї черги)
- State: **Enabled**

### Що має бути видно на Environment variables (другий скрін або той самий, якщо вміщається)

- `BUCKET` = `successfulsuccess-lab8-payments-378600555796`
- `TOPIC_ARN` = `…:lab8-payment-alerts`
- `ALERT_THRESHOLD` = `0.10`
- `STREAM_PREFIX` = `stream`

**Сенс:** cloud-consumer читає з черги і пише в lake + алертить.

---

## Скрін P4-4 — Lambda Monitor (що реально відпрацьовувала)

### Куди

1. Та сама функція `lab8-payments-stream-processor`  
2. Вкладка **Monitor**  
3. Графіки **Invocations** / **Errors** (останні години)

### Що має бути видно

- **Invocations** > 0 (після нашого прогону були десятки)  
- **Errors** ≈ 0  

Якщо графіки порожні — у фільтрі часу постав Last 1 day / 3 hours.

---

## Скрін P4-5 — S3: landed stream files

### Куди

1. Services → **S3** → Buckets  
2. Bucket **`successfulsuccess-lab8-payments-378600555796`**  
3. Зайди в префікс **`stream/`** → **`raw/`** → **`dt=2026-11-01/`** → **`hour=17/`** (або який hour є)

### Що має бути видно

- Багато об’єктів `batch-20261101T….jsonl`
- Size у кілобайтах (не порожні)
- Повний шлях у breadcrumbs:  
  `… / stream / raw / dt=2026-11-01 / hour=…`

Опційно кликни один файл → Open / Download preview: рядки JSON з `invoiceId`, `status`.

**Сенс:** stream реально потрапив у data lake.

---

## Скрін P4-6 — Athena: counts по stream

### Куди

1. Services → **Athena** → **Query editor**  
2. Data source: **AwsDataCatalog**  
3. Database: **`lab8`**  
4. У списку Tables має бути **`payments_stream`** (якщо немає — спочатку виконай SQL з `lab8/part4/01_create_stream_table.sql`)  
5. Встав і Run:

```sql
SELECT
  COUNT(*) AS events,
  COUNT(DISTINCT invoiceId) AS invoices,
  SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) AS failures,
  ROUND(100.0 * SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_pct
FROM lab8.payments_stream;
```

### Що має бути видно

У **Results**:

| events | invoices | failures | failure_pct |
|-------:|---------:|---------:|------------:|
| ~2510 | ~2440 | ~300 | **~11.95** |

На скріні мають бути і SQL зліва/зверху, і таблиця Results знизу.  
Workgroup/Output location може лишатись `s3://…/athena-results/`.

---

## Скрін P4-7 — Athena: failure rate by paymentMethod

### Куди

Той самий Athena Query editor, database `lab8`. Run:

```sql
SELECT
  paymentMethod,
  COUNT(*) AS n,
  SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) AS failures,
  ROUND(1.0 * SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) / COUNT(*), 4) AS failure_rate
FROM lab8.payments_stream
GROUP BY paymentMethod
ORDER BY failure_rate DESC;
```

### Що має бути видно

Рядки `monobank`, `google_pay`, `card`, `apple_pay` з **`failure_rate` > 0.10** (типу 0.11–0.13).

Це обґрунтовує SNS alerts (>10%).

---

## Скрін P4-8 — SNS alerts (опційно, але добре)

### Варіант A — Topic

1. Services → **SNS** → **Topics**  
2. Кликни **`lab8-payment-alerts`**

**Видно:** ім’я topic + ARN `…:lab8-payment-alerts`.

### Варіант B — CloudWatch metric (краще як “доказ publish”)

1. Services → **CloudWatch** → **Metrics** → All metrics  
2. SNS → Topic Metrics → TopicName = **`lab8-payment-alerts`**  
3. Метрика **NumberOfMessagesPublished**

**Видно:** графік з ненульовими publish за час експерименту (~139 у нашому вікні).

---

## Мінімальний набір Part 4 для LMS

Якщо ліміт скрінів:

1. **P4-1** діаграма  
2. **P4-3** Lambda + SQS trigger  
3. **P4-5** S3 `stream/raw/…`  
4. **P4-6** Athena counts (~2510, ~11.95%)  

Решту закрий текстом у `docs/lab8-part4-answers.md`.

---

## Підписи під скріни (скопіюй у LMS)

- P4-1: Architecture SQS→Lambda→S3→Athena (+SNS); Kinesis/Firehose blocked by SCP  
- P4-2: Queue `lab8-payments-stream`  
- P4-3: Lambda `lab8-payments-stream-processor` triggered by SQS  
- P4-5: Raw JSONL batches under `s3://…/stream/raw/`  
- P4-6: Athena `payments_stream` — 2510 events, 11.95% failures  
- P4-7: All payment methods >10% failure → alerts  
- P4-8: SNS `lab8-payment-alerts`  
