# Lab 8 — що в загальному здати в LMS (Moodle)

Якщо на Moodle **окремі** завдання Part 2 / 3 / 4 — грузи по частинах.  
Якщо **одне** завдання на всю Lab 8 — один zip + короткий README.

---

## 1. Один zip (рекомендована структура)

Назви zip наприклад: `Marta_Lab8_BigData.zip`

```text
Lab8/
├── README.txt                          ← 5–10 рядків: що всередині + 2 примітки нижче
├── answers/
│   ├── lab8-part2-answers.md
│   ├── lab8-part3-answers.md
│   └── lab8-part4-answers.md
├── experiments/                        ← логи Part 3
│   ├── exp0_consumer.txt
│   ├── exp1_consumer_part1.txt
│   ├── exp1_consumer_part2.txt
│   ├── exp2_c1.txt
│   ├── exp2_c2.txt
│   ├── exp3_consumer.txt
│   ├── exp4_consumer.txt
│   └── exp4_consumer_grace120.txt
├── code/
│   ├── streaming/                      ← docker-compose.yml, producer.py, consumer.py, requirements.txt
│   ├── part4/                          ← lambda_function.py, sqs_producer.py, *.sql
│   └── athena/                         ← опційно SQL Part 2
└── screenshots/
    ├── part2/                          ← якщо Part 2 ще не зданий окремо
    ├── part3/
    └── part4/
```

### Дві обов’язкові примітки в README / answers

1. Course bucket `ucu-ooad-lab8-payments` → **Access Denied** → synthetic dataset у  
   `s3://successfulsuccess-lab8-payments-378600555796/payments/`  
2. **Kinesis / Firehose** → SCP deny на Free → еквівалент **SQS + Lambda + S3 + Athena + SNS**

Джерела відповідей уже в репо:

- `docs/lab8-part2-answers.md`
- `docs/lab8-part3-answers.md`
- `docs/lab8-part4-answers.md`

Логи: `lab8/experiments/`  
Код: `lab8/streaming/`, `lab8/part4/`, `lab8/athena/`

---

## 2. Скріни — скільки і які

### Part 2 (якщо ще треба; у тебе вже є `lab8-part2-screenshots.zip`)

Athena queries (count / turnover / failure / peak / late / parquet scanned) + Glue crawler/schema + S3 `payments/`.

### Part 3 (локальний stream) — гайд: `docs/lab8-part3-screenshots-guide.md`

| Код | Що |
|-----|-----|
| P3-1 | Redpanda Console → Topics → `payments` *(у тебе вже є)* |
| P3-2 | Messages з JSON (опційно) |
| P3-3 | хвіст `exp0_consumer.txt` → SUMMARY events=6000 |
| P3-4 | exp1 part1 `2000` + part2 `4000` |
| P3-5 | exp2_c1 + exp2_c2 (різні partitions, сума 6000) |
| P3-6 | exp3 ALERT + alerts=279 |
| P3-7 | exp4 rejected_late **181** vs **0** |

**Мінімум Part 3:** P3-1, P3-5, P3-6, P3-7 (+ текст answers).

### Part 4 (cloud) — гайд: `docs/lab8-part4-screenshots-guide.md`

| Код | Куди в AWS | Що доводить |
|-----|------------|-------------|
| P4-1 | діаграма з answers | архітектура пайплайна |
| P4-2 | SQS → `lab8-payments-stream` | буфер stream |
| P4-3 | Lambda → Triggers SQS | обробник |
| P4-4 | Lambda → Monitor | були invocations |
| P4-5 | S3 → `stream/raw/dt=…` | дані в lake |
| P4-6 | Athena → counts ~2510 / 11.95% | SQL по stream |
| P4-7 | Athena → by method >10% | підстава alerts |
| P4-8 | SNS topic / CW publishes | alerts (опційно) |

**Мінімум Part 4:** P4-1, P4-3, P4-5, P4-6.

---

## 3. Що перевіряючий шукає по суті (не лише скріни)

| Частина | Суть |
|---------|------|
| Part 2 | batch lake: Glue/Athena над payments, dedup, метрики, JSON≪Parquet по scanned bytes |
| Part 3 | Kafka-API stream: вікна 1 хв, dedup, alert >10%, late grace; експерименти stop/resume, 2 consumers, fail-boost, grace |
| Part 4 | cloud ingest → S3 → Athena + порівняння з Part 3; діаграма |

---

## 4. Чеклист перед Upload на Moodle

- [ ] Zip відкривається, немає гігабайтів `lab8/data/` (їх **не** клади — лише код/логи/answers/screenshots)  
- [ ] Три MD з answers всередині  
- [ ] `experiments/*.txt` всередині  
- [ ] Скріни Part 3 + Part 4 (Part 2 — якщо потрібно)  
- [ ] README з Access Denied + SCP Kinesis note  
- [ ] Імена скрінів зрозумілі: `p3-exp4-grace.png`, `p4-athena-counts.png`, …  

---

## 5. Після прийняття (опційно)

- AWS cleanup — команди в кінці `docs/lab8-part4-answers.md`  
- Local: `cd lab8/streaming && docker compose down`
