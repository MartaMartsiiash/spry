"""Lambda entry point for the agenda parser. No VPC, no database.

The browser POSTs {text, today, tz} with a Cognito access token. The handler
returns validated JSON for the form; saving goes through the main API.

CORS is configured on the Function URL only — do not set ACAO here, or browsers
see a duplicate Access-Control-Allow-Origin and fail the fetch.
"""

from __future__ import annotations

import json
import logging
import time
from datetime import date
from typing import Any

from app.ai.agenda import PROMPT_VERSION, AgendaParseError, parse_agenda
from app.ai.cost import cost_usd
from app.auth import AuthError, AuthNotConfiguredError, verify_cognito_token_sync
from app.config import settings

log = logging.getLogger()
log.setLevel(logging.INFO)

MAX_TEXT_CHARS = 10_000


def _header(headers: dict[str, Any] | None, name: str) -> str:
    if not headers:
        return ""
    lower = {str(k).lower(): v for k, v in headers.items()}
    value = lower.get(name.lower(), "")
    return value if isinstance(value, str) else ""


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event: dict, context: object) -> dict:
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 204, "body": ""}

    try:
        user = verify_cognito_token_sync(_header(event.get("headers"), "authorization"))
    except (AuthError, AuthNotConfiguredError) as exc:
        return _response(401, {"error": str(exc)})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "body must be JSON"})

    text = body.get("text")
    if not isinstance(text, str) or not text.strip():
        return _response(400, {"error": "text is required"})
    if len(text) > MAX_TEXT_CHARS:
        return _response(413, {"error": f"text longer than {MAX_TEXT_CHARS} characters"})

    try:
        today = date.fromisoformat(str(body["today"]))
        tz = str(body["tz"])
    except (KeyError, TypeError, ValueError):
        return _response(400, {"error": "today (YYYY-MM-DD) and tz are required"})

    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except AgendaParseError as e:
        return _response(422, {"error": str(e)})
    except Exception as e:  # throttling, network, etc.
        log.exception("agenda parse failed")
        message = str(e)
        status = 429 if "Throttl" in type(e).__name__ or "429" in message else 502
        return _response(status, {"error": message})

    log.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": user.sub,
                "model": settings.parser_model,
                "prompt_version": PROMPT_VERSION,
                **usage,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "cost_usd": cost_usd(settings.parser_model, usage),
            }
        )
    )
    return _response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": settings.parser_model,
            "prompt_version": PROMPT_VERSION,
        },
    )
