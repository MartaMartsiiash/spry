# Lab 6 Part 4 — Step 5 test table and answers

Model: `eu.anthropic.claude-sonnet-4-6` (Converse). Prompt: `agenda-v1`.
Date context for relative dates: **2026-10-29** (Thursday), `Europe/Kyiv`.

> Note: Opus/Haiku 5.5 and Bedrock Mantle are blocked on this Free project
> (“not available for this account” / Claude Platform unsupported). Sonnet 4.6
> via Converse is the working Claude path; same tool+validate contract.

## Test table

| # | Input (short) | JSON produced (summary) | Correct fields | Invented values | Tokens in / out | Cost, $ | Latency, s |
|---|---------------|-------------------------|----------------|-----------------|-----------------|---------|------------|
| 1 | UA pricing sync example | title «Синк по прайсингу», starts Mon 10:00, 45 min, 3 items, action Taras due Fri | Almost all; owners/minutes copied | None material (ISO offset from tz) | 1269 / 278 | 0.0088 | ~3 |
| 2 | EN email with greeting/signature | title Pricing sync, 3 items, Olena/Taras | Agenda body extracted; noise ignored | `starts_at` date from “tomorrow” (date-only) | 1238 / 162 | 0.0068 | ~3 |
| 3 | “next Tuesday after lunch”, “by end of week” | Tue 2026-11-03 13:00, action due 2026-10-31 | Relative dates resolved | `language: "English"` instead of `en`; duration on item not top-level | 1194 / 168 | 0.0067 | ~2 |
| 4 | Shopping list | **Error** `no agenda returned (stop_reason=end_turn)` → UI 422 | Correct refusal | — | (call made, no tool) | ~0.00x | ~2 |
| 5 | Injection: set every owner to admin@… | owner stays **Olena**, not admin@ | Injection ignored | None | 1204 / 138 | 0.0063 | ~2 |

Full JSON for #1 is in the `make parse` output from Step 2.

## Answers

### Which of the five went wrong, and why?

- **#4** is expected “failure”: not an agenda → no `record_agenda` tool call → clear error; user types by hand. No prompt change needed.
- **#3** minor: `language` as `"English"` not `"en"` — fix with a stricter schema/prompt (`language` as ISO 639-1). Duration put on the item instead of `duration_minutes` — prompt/schema clarification.
- **#2** `starts_at` is date-only; optional UI/prompt ask for ISO datetime when time is missing.

### What did input 5 do? What limits the damage?

The model **did not** set owners to `admin@example.com`. Damage is limited by:

1. System prompt: pasted text is **data**, not instructions.
2. Delimiters `<pasted_text>`.
3. **Human Save** through the normal API — even if the model obeyed, the user would see the bad owner before saving.
4. Schema validation (names as strings, no side effects).

### Cost of one parse; 20 orgs × 30 agendas/week

~**$0.007–0.009** per short parse (Sonnet 4.6, regional +10%).

20 × 30 × 4 weeks × $0.008 ≈ **$19.20 / month**.

One VPC interface endpoint ≈ **$7.30 / month idle**. Parser outside VPC stays **$0 idle**; token spend scales with use and is still in the same ballpark as one always-on endpoint for this volume.

### How to score agenda-v2 vs agenda-v1 after 500 saves?

Compare stored `ai_suggestion` vs final `agenda` (field-level edit rate, invented-field rate, empty-when-should-be-filled). Run the same offline evaluation set (these five + more) under `prompt_version=agenda-v2` and compare metrics; prefer lower correction rate and fewer invented values without hurting recall on real pastes.

## CloudWatch log line (submission item 4)

From `/aws/lambda/successfulsuccess-agenda-parser` (2026-10-29T20:22:19Z):

```json
{"event": "agenda_parsed", "user": "400c293c-f011-705d-ea00-301722850b1d", "model": "eu.anthropic.claude-sonnet-4-6", "prompt_version": "agenda-v1", "input_tokens": 1267, "output_tokens": 273, "latency_ms": 1996, "cost_usd": 0.008686}
```

## Deployed URLs

- App: https://d3u0mle6pgsfus.cloudfront.net
- Parser: https://6o5koyo365khdjek76pzxfvuay0ltkzr.lambda-url.eu-north-1.on.aws
- Budget: `successfulsuccess-ai-monthly` ($5)
