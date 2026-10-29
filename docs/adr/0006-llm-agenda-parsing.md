# ADR 0006 — LLM agenda parsing on Bedrock

## Context

Real agendas arrive as email, chat messages, or notes — not as forms. We need a
feature where the user pastes free text, an LLM turns it into a structured
agenda, the UI shows a pre-filled form, and the user checks and saves.

Constraints:

- No NAT gateway (Lab 4: "$0 when idle"). The parser must reach Bedrock without
  a VPC interface endpoint (~$7.30/month) either.
- Every parse costs money (tokens). The endpoint must be authenticated and length-limited.
- Pasted text comes from outside (calendar invites, forwarded mail). It is data,
  not instructions (prompt injection).
- The model can be wrong with HTTP 200. The person must stay in charge of writes.

## Decision

1. **Model:** Claude via Amazon Bedrock **Converse** API, model id in
   `PARSER_MODEL` (default `eu.anthropic.claude-sonnet-4-6`). Tool
   `record_agenda` with a Pydantic schema; validate and retry once.
   *Why not Mantle / Opus 5.5 as in the lab text?* On this Free-plan project,
   Claude Platform (bedrock-mantle) and Opus/Haiku 5.5 invoke are blocked
   ("not available for this account" / console "Access not supported").
   Sonnet 4.6 via Converse works and keeps the same tool+validate contract.
2. **Parser outside the VPC:** a separate Lambda (`infra/ai.yml`) with a function
   URL, no `VpcConfig`, same container image, handler `app.ai.agenda_lambda.handler`.
   It calls Bedrock over the public endpoint and returns JSON only.
3. **The model never writes:** Save goes through `PUT /api/v1/meetings/{id}/agenda`
   on the existing API into Aurora (`agenda` + `ai_suggestion` JSONB). The
   suggestion (model, prompt version, raw parse) is stored next to the final agenda
   so corrections become a quality signal without an extra feedback click.

## Alternatives considered

| Alternative | Why it lost |
|-------------|-------------|
| Call Bedrock from the API Lambda through a VPC interface endpoint | Idle cost (~$7.30/month) breaks "$0 when idle"; the parser does not need the database |
| Anthropic Claude API directly (API key) | Another secret to store and rotate; bill outside AWS Budgets / Cost Explorer |
| Regex / hand-written parser | Breaks on Ukrainian/English mix, relative dates, email noise; high maintenance |

## Consequences

- **Cost:** logged per parse (`input_tokens`, `output_tokens`, `cost_usd`, latency).
  Roughly cents for Opus, fractions of a cent for Haiku on short pastes.
- **Observability:** one JSON CloudWatch line per successful parse (`agenda_parsed`).
- **When Bedrock is down:** the user types the agenda by hand in the same form;
  meetings CRUD and the rest of Spry keep working.
- **Security:** Cognito access token required; text > 10 000 characters → 413;
  pasted text delimited in the prompt as data; `$5` monthly budget alarm to email
  (created with `aws budgets` / `make aws-ai-budget` — `AWS::Budgets::Budget` is
  not a recognised resource type in this Free-plan CloudFormation).
- **Quality loop:** diff between `ai_suggestion` and saved `agenda` after enough
  production saves becomes the evaluation set for prompt `agenda-v2`.
