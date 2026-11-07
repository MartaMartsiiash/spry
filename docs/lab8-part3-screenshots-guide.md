# Part 3 — детально: куди заходити і що має бути видно на скрінах

Перед усім (один раз):

```bash
cd lab8/streaming
docker compose up -d
```

Дочекайся `healthy` у `docker compose ps`.  
UI Console: **http://localhost:8080** у браузері.

Логи експериментів уже є — їх можна просто відкрити в Cursor/VS Code і зняти скрін хвоста файлу (не обов’язково переганяти все знову).

Шлях до логів:

`/Users/jabkoberegovo/Documents/ооа/lab2/SuccessfulSuccess/lab8/experiments/`

---

## Скрін P3-1 — Topic `payments` у Redpanda Console

### Куди

1. Відкрий **http://localhost:8080**
2. Ліве меню → **Topics** (іноді “Kafka topics”)
3. Кликни topic з ім’ям **`payments`**

### Що має бути видно

- Назва topic: **`payments`**
- **Partitions**: `1` (після останніх exp0/1/3/4) або `3` (якщо topic лишився після exp2) — обидва ок; у відповіді можна написати “для exp2 було 3 partitions”
- Є сторінка topic (Overview / Messages / Configuration)
- Бажано: ненульовий розмір / message count, якщо після експериментів дані ще в topic

### Як зняти

Весь вікно браузера з лівим меню + заголовок `payments`.

---

## Скрін P3-2 — Приклад повідомлень у topic

### Куди

1. Той самий topic **`payments`**
2. Вкладка **Messages** (або “Consume” / “Preview”)
3. Якщо порожньо — спочатку швидко наповни:

```bash
cd lab8/streaming
docker compose exec -T redpanda rpk topic delete payments || true
docker compose exec -T redpanda rpk topic create payments -p 1 -r 1
python3 producer.py --rate 200 --limit 200
```

Онови Messages у Console.

### Що має бути видно

Хоча б 1–3 записи JSON, у тілі є поля на кшталт:

- `invoiceId`
- `status` (`success` / `failure` / …)
- `paymentMethod` (`card`, `apple_pay`, …)
- `modifiedDate`, `receivedAt`
- `merchantId` / `merchantName`

Key повідомлення = `invoiceId` (у колонці Key, якщо Console її показує).

---

## Скрін P3-3 — Baseline (нормальна робота consumer)

### Куди (без перегону)

1. Відкрий файл  
   `lab8/experiments/exp0_consumer.txt`
2. Прокрути **вниз до кінця**
3. Зніми останні ~15–30 рядків

### Що має бути видно

Обов’язково рядок:

```text
SUMMARY closed_windows=93 alerts=58 events=6000 duplicates=61 rejected_late_total=0
```

Добре, якщо вище видно блоки вікон:

```text
=== WINDOW 2026-10-01T... → ... ===
  card: n=... failures=... rate=...
```

і рядок старту:

```text
consuming topic=payments group=lab8-exp0c late_grace_sec=120
```

**Сенс для викладача:** consumer читає topic, ріже event-time вікна по 1 хв, інколи алертить (>10% fail).

---

## Скрін P3-4 — Experiment 1 (stop → resume, без втрат)

Потрібні **два** хвости логів поруч (два вікна IDE або один скрін з двома панелями).

### Куди

| Панель | Файл |
|--------|------|
| Ліворуч | `lab8/experiments/exp1_consumer_part1.txt` → кінець файлу |
| Праворуч | `lab8/experiments/exp1_consumer_part2.txt` → кінець файлу |

### Що має бути видно

**Part 1:**

```text
SUMMARY ... events=2000 ...
```

**Part 2:**

```text
SUMMARY ... events=4000 ...
```

На скріні або в підписі додай: **2000 + 4000 = 6000** (усе з одного прогону producer на 6000, той самий consumer group — після стопу продовжили з offset).

### Якщо хочеш “живий” скрін терміналу

```bash
# уже після прогону достатньо:
tail -5 lab8/experiments/exp1_consumer_part1.txt
tail -5 lab8/experiments/exp1_consumer_part2.txt
```

---

## Скрін P3-5 — Experiment 2 (два consumers, один group)

Знову **два** вікна поруч.

### Куди

| Панель | Файл |
|--------|------|
| C1 | `lab8/experiments/exp2_c1.txt` → кінець |
| C2 | `lab8/experiments/exp2_c2.txt` → кінець |

### Що має бути видно

**C1:**

```text
SUMMARY ... events=3903 ...
assigned_partitions= [..., partition=0..., partition=1...]
```

**C2:**

```text
SUMMARY ... events=2097 ...
assigned_partitions= [..., partition=2...]
```

Перевірка: **3903 + 2097 = 6000**, partitions **різні** (не обидва на одних і тих самих).

**Сенс:** consumer group ділить partitions між інстансами.

Опційно третім крихітним скріном: у Console → Topics → `payments` → видно **3 partitions** (якщо пересоздаси topic з `-p 3` перед демо).

---

## Скрін P3-6 — Experiment 3 (багато ALERT)

### Куди

1. Відкрий `lab8/experiments/exp3_consumer.txt`
2. Знайди кілька рядків з `*** ALERT` (Cmd+F → `ALERT`)
3. Зніми фрагмент з 5–10 ALERT + **кінець з SUMMARY**

Або два скріни: (a) середина з ALERT, (b) SUMMARY.

### Що має бути видно

Рядки виду:

```text
  google_pay: n=7 failures=3 rate=42.9%  *** ALERT: failures > 10% ***
```

і в кінці:

```text
SUMMARY closed_windows=93 alerts=279 events=6000 duplicates=52 rejected_late_total=0
```

Порівняння з baseline: там було **`alerts=58`**, тут **`alerts=279`** (після `--fail-boost 0.35`).

---

## Скрін P3-7 — Experiment 4 (late grace 0 vs 120)

Знову **два** хвости поруч.

### Куди

| Панель | Файл |
|--------|------|
| grace = 0 | `lab8/experiments/exp4_consumer.txt` → кінець |
| grace = 120 | `lab8/experiments/exp4_consumer_grace120.txt` → кінець |

### Що має бути видно

**Grace 0:**

```text
SUMMARY ... events=5200 ... rejected_late_total=181
```

**Grace 120:**

```text
SUMMARY ... events=5200 ... rejected_late_total=0
```

Одне й те саме число `events=5200`, різниця лише в **`rejected_late_total`**.

**Сенс:** при `late_grace_sec=0` запізнілі події відкидаються; при 120 с — ще приймаються.

---

## Що НЕ обов’язково знімати в Part 3

- Docker Desktop зі статусом контейнерів (корисно, але не суть)
- увесь гігантський лог вікон (достатньо хвоста + ALERT-фрагмента)
- код `producer.py` / `consumer.py` окремими скрінами — краще прикріпити файли в zip

---

## Мінімальний набір, якщо Moodle обмежує кількість фото

1. **P3-1** Console topic `payments`  
2. **P3-5** два consumers + різні partitions  
3. **P3-6** ALERT + `alerts=279`  
4. **P3-7** `rejected_late` 181 vs 0  

Exp1 можна закрити таблицею в `lab8-part3-answers.md` + одним скріном двох SUMMARY.

---

## Підпис під скрінами (скопіюй у Moodle)

- P3-1: Redpanda Console, topic `payments`  
- P3-4: same group resume — 2000 then 4000, total 6000, no loss  
- P3-5: consumer group share — C1 partitions 0–1 (3903), C2 partition 2 (2097)  
- P3-6: fail-boost → failure share >10% alerts (279)  
- P3-7: late grace 0 rejects 181; grace 120 rejects 0  
