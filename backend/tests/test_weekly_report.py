"""The weekly CSV, the builder's event shapes, and the two small functions."""

import json
from datetime import datetime
from pathlib import Path
from unittest import mock
from zoneinfo import ZoneInfo

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Meeting, Participant, User
from app.reports.enqueue import handler as enqueue
from app.reports.lambda_handler import handler, read_request
from app.reports.mailer import handler as mailer
from app.reports.weekly import (
    normalize_week,
    previous_iso_week,
    render_weekly_report,
    report_key,
)

KYIV = ZoneInfo("Europe/Kyiv")
ROOT = Path(__file__).resolve().parents[2]


def _at(year: int, month: int, day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(year, month, day, hour, minute, tzinfo=KYIV)


async def _add(
    session: AsyncSession,
    *,
    owner: str,
    name: str,
    start: datetime,
    end: datetime,
    participants: list[tuple[str, str | None]],
) -> None:
    session.add(
        Meeting(
            owner_id=owner,
            name=name,
            starts_at=start,
            ends_at=end,
            participants=[
                Participant(name=person, email=email, position=index)
                for index, (person, email) in enumerate(participants)
            ],
        )
    )
    await session.commit()


def test_week_helpers_reject_garbage_and_keep_one_key():
    assert normalize_week("2026-W4") == "2026-W04"
    assert report_key("2026-W40") == "reports/2026-W40.csv"
    # Thursday 15 Oct 2026 is ISO week 42, so the report with no week is week 41.
    now = datetime(2026, 10, 15, 1, 30, tzinfo=ZoneInfo("UTC"))
    assert previous_iso_week(now) == "2026-W41"
    with pytest.raises(ValueError):
        normalize_week("2026-W99")
    with pytest.raises(ValueError):
        normalize_week("last week")


def test_schedule_message_stays_trigger_schedule_after_the_queue():
    event = {"Records": [{"body": '{"week": null, "source": "schedule"}'}]}
    assert read_request(event) == ("schedule", None)


def test_manual_message_is_trigger_sqs_and_direct_invoke_still_works():
    queued = {"Records": [{"body": '{"week": "2026-W39", "source": "manual"}'}]}
    assert read_request(queued) == ("sqs", "2026-W39")
    assert read_request({"week": "2026-W39", "source": "schedule"}) == ("schedule", "2026-W39")
    assert read_request({"week": "2026-W39"}) == ("direct", "2026-W39")


def test_forced_failure_raises_before_the_report_is_built(monkeypatch):
    monkeypatch.setenv("REPORT_FAIL_WEEK", "2026-W39")

    def _unexpected(week: str) -> bytes:
        raise AssertionError(f"built {week}")

    monkeypatch.setattr("app.reports.lambda_handler.build_weekly_report", _unexpected)
    event = {"Records": [{"body": '{"week": "2026-W39", "source": "manual"}'}]}
    with pytest.raises(RuntimeError, match="2026-W39"):
        handler(event, None)


def test_builder_writes_one_key_per_week(monkeypatch):
    monkeypatch.delenv("REPORT_FAIL_WEEK", raising=False)
    monkeypatch.setenv("REPORTS_BUCKET", "reports-bucket")
    monkeypatch.setattr("app.reports.lambda_handler.build_weekly_report", lambda week: b"csv")
    stored = mock.Mock()
    monkeypatch.setattr("app.reports.lambda_handler.boto3.client", lambda _service: stored)
    event = {"Records": [{"body": '{"week": "2026-W39", "source": "manual"}'}]}

    result = handler(event, None)

    assert result == {
        "results": [{"week": "2026-W39", "key": "reports/2026-W39.csv", "trigger": "sqs"}]
    }
    kwargs = stored.put_object.call_args.kwargs
    assert kwargs["Bucket"] == "reports-bucket"
    assert kwargs["Key"] == "reports/2026-W39.csv"
    assert kwargs["Body"] == b"csv"


def test_mailer_attaches_the_csv_and_does_not_write(monkeypatch):
    body = mock.Mock()
    body.read.return_value = b"week,meetings\n"
    s3 = mock.Mock()
    s3.get_object.return_value = {"Body": body}
    ses = mock.Mock()

    def client(name: str):
        return {"s3": s3, "sesv2": ses}[name]

    monkeypatch.setattr("app.reports.mailer.boto3.client", client)
    monkeypatch.setenv("SENDER", "reports@example.com")
    monkeypatch.setenv("RECIPIENTS", "marta@example.com")
    event = {
        "Records": [{"s3": {"bucket": {"name": "b"}, "object": {"key": "reports/2026-W40.csv"}}}]
    }

    result = mailer(event, None)

    assert result["trigger"] == "s3"
    s3.put_object.assert_not_called()
    raw = ses.send_email.call_args.kwargs["Content"]["Raw"]["Data"]
    assert b"2026-W40.csv" in raw
    assert ses.send_email.call_args.kwargs["Destination"]["ToAddresses"] == ["marta@example.com"]


def test_mailer_ignores_a_key_outside_reports(monkeypatch):
    ses = mock.Mock()
    monkeypatch.setattr("app.reports.mailer.boto3.client", lambda _name: ses)
    event = {"Records": [{"s3": {"bucket": {"name": "b"}, "object": {"key": "requests/1.json"}}}]}

    assert mailer(event, None)["skipped"] == "requests/1.json"
    ses.send_email.assert_not_called()


def test_enqueue_forwards_the_command_and_does_not_write(monkeypatch):
    body = mock.Mock()
    body.read.return_value = json.dumps({"id": "1", "week": "2026-W41", "source": "api"}).encode()
    s3 = mock.Mock()
    s3.get_object.return_value = {"Body": body}
    sqs = mock.Mock()

    def client(name: str):
        return {"s3": s3, "sqs": sqs}[name]

    monkeypatch.setattr("app.reports.enqueue.boto3.client", client)
    monkeypatch.setenv("QUEUE_URL", "https://sqs.example/queue")
    event = {"Records": [{"s3": {"bucket": {"name": "b"}, "object": {"key": "requests/1.json"}}}]}

    enqueue(event, None)

    s3.put_object.assert_not_called()
    sent = json.loads(sqs.send_message.call_args.kwargs["MessageBody"])
    assert sent == {"week": "2026-W41", "source": "api"}


def test_inline_functions_match_the_modules():
    template = (ROOT / "infra" / "reports.yml").read_text()
    for name in ("mailer.py", "enqueue.py"):
        source = (ROOT / "backend" / "app" / "reports" / name).read_text()
        for line in source.splitlines():
            if line.strip():
                assert line.strip() in template, line


async def test_weekly_csv_compares_weeks_and_breaks_down_people(session: AsyncSession):
    session.add_all(
        [
            User(id="user-a", email="marta@example.com", name="Marta"),
            User(id="user-b", email="taras@example.com", name="Taras"),
        ]
    )
    await session.commit()
    await _add(
        session,
        owner="user-a",
        name="Sprint planning",
        start=_at(2026, 9, 28, 10),
        end=_at(2026, 9, 28, 12),
        participants=[("Ostap", "ostap@example.com"), ("Iryna", None)],
    )
    await _add(
        session,
        owner="user-a",
        name="Retro",
        start=_at(2026, 9, 30, 9),
        end=_at(2026, 9, 30, 10, 30),
        participants=[("Ostap", "Ostap@example.com")],
    )
    await _add(
        session,
        owner="user-b",
        name="Workshop",
        start=_at(2026, 9, 29, 9),
        end=_at(2026, 9, 29, 15),
        participants=[("Iryna", None)],
    )
    # Sunday of the previous week, and Monday of the next one: neither is week 40.
    await _add(
        session,
        owner="user-a",
        name="Standup",
        start=_at(2026, 9, 27, 9),
        end=_at(2026, 9, 27, 10),
        participants=[("Ostap", "ostap@example.com")],
    )
    await _add(
        session,
        owner="user-a",
        name="Next week",
        start=_at(2026, 10, 5, 9),
        end=_at(2026, 10, 5, 10),
        participants=[("Iryna", None)],
    )

    text = (await render_weekly_report(session, "2026-W40")).decode()
    rows = [line.split(",") for line in text.splitlines() if line]

    summary = next(row for row in rows if row[0] == "summary")
    assert summary[1] == "2026-W40"
    assert summary[4] == "3"
    assert summary[5] == "9.50"
    assert summary[6] == "2026-W39"
    assert summary[7] == "1"
    assert summary[8] == "1.00"
    assert summary[9] == "2"
    assert summary[10] == "8.50"

    longest = [row for row in rows if row[0] == "longest"]
    assert [row[2] for row in longest] == ["Workshop", "Sprint planning", "Retro"]
    assert longest[0][4] == "6.00"
    assert longest[0][5] == "1"

    people = {row[1]: (row[2], row[3]) for row in rows if row[0] == "person"}
    assert people["Iryna"] == ("2", "8.00")
    assert people["ostap@example.com"] == ("2", "3.50")

    owners = {row[1]: (row[2], row[3]) for row in rows if row[0] == "owner"}
    assert owners["taras@example.com"] == ("1", "6.00")
    assert owners["marta@example.com"] == ("2", "3.50")

    again = await render_weekly_report(session, "2026-w40")
    assert again.decode() == text


async def test_empty_week_is_a_zero_report(session: AsyncSession):
    text = (await render_weekly_report(session, "2026-W01")).decode()
    summary = next(line for line in text.splitlines() if line.startswith("summary,"))
    assert ",2026-W01," in summary
    assert ",0,0.00," in summary
