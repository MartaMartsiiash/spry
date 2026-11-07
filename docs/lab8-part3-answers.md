# Lab 8 Part 3 — Redpanda streaming (local)

Stack: `lab8/streaming/docker-compose.yml` (Redpanda + Console on :8080),  
`producer.py` / `consumer.py` (`kafka-python-ng`), topic `payments`.

Consumer logic (event-time):

- 1-minute windows on `modifiedDate`
- exact-line dedup inside a window
- latest status per `invoiceId`
- alert if failures / payments for a `paymentMethod` **> 10%**
- late arrivals controlled by `--late-grace-sec` (watermark = max event-time seen)

Raw logs: `lab8/experiments/`.

## Baseline

- Produced **6000** events (1 partition, sorted by event-time).
- `SUMMARY closed_windows=93 alerts=58 events=6000 duplicates=61 rejected_late_total=0`

## Experiment 1 — stop consumer, resume same group (no loss)

1. Produce 6000, consume with `--max-messages 2000` → `events=2000`
2. Resume same `--group lab8-exp1c` → `events=4000`

**2000 + 4000 = 6000**. Offsets committed; resume continues without replaying or skipping.

## Experiment 2 — two consumers, one group (3 partitions)

| Consumer | Partitions | Events |
|----------|------------|-------:|
| C1 | 0, 1 | 3903 |
| C2 | 2 | 2097 |
| **Total** | | **6000** |

Partitions are split by the consumer group; work is shared, each event processed once.

## Experiment 3 — raise failure rate (`--fail-boost 0.35`)

- `SUMMARY … alerts=279 events=6000 …`
- Many `*** ALERT: failures > 10% ***` lines in `exp3_consumer.txt` (vs ~58 alerts in baseline).

## Experiment 4 — late grace 0 vs 120 s

Producer injects ~200 events that are **45–90 s behind** the watermark (`--inject-late`).

| Config | `rejected_late_total` | Notes |
|--------|----------------------:|-------|
| `--late-grace-sec 0` | **181** | late arrivals dropped |
| `--late-grace-sec 120` | **0** | same late events still accepted |

## How to re-run

```bash
cd lab8/streaming
docker compose up -d
pip3 install -r requirements.txt
docker compose exec redpanda rpk topic create payments -p 1 -r 1   # or -p 3 for exp2
python3 producer.py --rate 800 --limit 6000
python3 consumer.py --group demo --late-grace-sec 120
```

Console UI: http://localhost:8080
