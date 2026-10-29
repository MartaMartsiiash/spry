"""Run parse_agenda from the laptop: make parse TEXT='...'"""

from __future__ import annotations

import json
import os
import sys
from datetime import date
from zoneinfo import ZoneInfo

from app.ai.agenda import format_parse_result, parse_agenda


def main() -> int:
    text = os.environ.get("TEXT") or (sys.argv[1] if len(sys.argv) > 1 else "")
    if not text.strip():
        print("Usage: make parse TEXT='your agenda text'", file=sys.stderr)
        return 2
    tz_name = os.environ.get("TZ", "Europe/Kyiv")
    today_raw = os.environ.get("TODAY")
    today = date.fromisoformat(today_raw) if today_raw else date.today()
    # Use the wall-clock date in the user's zone when TODAY is unset.
    if not today_raw:
        today = date.today()
        try:
            today = __import__("datetime").datetime.now(ZoneInfo(tz_name)).date()
        except Exception:
            pass
    agenda, usage = parse_agenda(text, today, tz_name)
    print(json.dumps(format_parse_result(agenda, usage), indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
