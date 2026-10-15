"""Query one ISO week of meetings and return the CSV. No AWS calls live here.

The caller decides the week. The same week always produces the same bytes for
the same database rows, and the handler always stores them at
``reports/<week>.csv``, so running the task twice overwrites one file.
"""

import asyncio
import csv
import io
import re
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.config import settings
from app.db import make_engine
from app.models import Meeting, User

_WEEK = re.compile(r"^(\d{4})-W(\d{1,2})$", re.IGNORECASE)


def normalize_week(week: str) -> str:
    """Turn ``2026-W40`` or ``2026-W4`` into the canonical ``2026-W04`` form."""
    match = _WEEK.fullmatch(week.strip())
    if match is None:
        raise ValueError("Week must look like 2026-W40.")
    year, number = int(match.group(1)), int(match.group(2))
    try:
        date.fromisocalendar(year, number, 1)
    except ValueError as exc:
        raise ValueError(f"{week} is not an ISO week.") from exc
    return f"{year}-W{number:02d}"


def week_window(week: str) -> tuple[datetime, datetime]:
    """Monday 00:00 inclusive through next Monday 00:00 exclusive, in the app timezone."""
    year_s, week_s = normalize_week(week).split("-W")
    monday = date.fromisocalendar(int(year_s), int(week_s), 1)
    start = datetime.combine(monday, time.min, tzinfo=settings.tz)
    end = datetime.combine(monday + timedelta(days=7), time.min, tzinfo=settings.tz)
    return start, end


def previous_iso_week(now: datetime | None = None) -> str:
    """The ISO week before the one that contains ``now`` (default: now, app timezone)."""
    current = (now or datetime.now(settings.tz)).astimezone(settings.tz)
    this_monday = current.date() - timedelta(days=current.weekday())
    previous_monday = this_monday - timedelta(days=7)
    iso = previous_monday.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def report_key(week: str) -> str:
    """One object per week. A second run replaces the file instead of adding one."""
    return f"reports/{normalize_week(week)}.csv"


def _hours(meeting: Meeting) -> float:
    return (meeting.ends_at - meeting.starts_at).total_seconds() / 3600


def _person_key(name: str, email: str | None) -> tuple[str, str]:
    """Email identifies a person across meetings; a name is the fallback."""
    if email and email.strip():
        return email.strip().lower(), email.strip()
    label = name.strip() or "unknown"
    return label.casefold(), label


async def _meetings_in(session: AsyncSession, start: datetime, end: datetime) -> list[Meeting]:
    """Meetings that *start* in the window, so one meeting belongs to one week."""
    result = await session.scalars(
        select(Meeting)
        .where(Meeting.starts_at >= start, Meeting.starts_at < end)
        .options(selectinload(Meeting.participants))
        .order_by(Meeting.starts_at.asc(), Meeting.name.asc())
    )
    return list(result)


def _totals(meetings: list[Meeting]) -> tuple[int, float]:
    return len(meetings), sum(_hours(meeting) for meeting in meetings)


async def render_weekly_report(session: AsyncSession, week: str) -> bytes:
    """CSV for ``week``: totals against the week before, the five longest, per person."""
    week = normalize_week(week)
    start, end = week_window(week)
    previous = previous_iso_week(start)
    previous_start, previous_end = week_window(previous)

    meetings = await _meetings_in(session, start, end)
    earlier = await _meetings_in(session, previous_start, previous_end)
    count, hours = _totals(meetings)
    previous_count, previous_hours = _totals(earlier)

    longest = sorted(
        meetings,
        key=lambda meeting: (-_hours(meeting), meeting.starts_at, meeting.name),
    )[:5]

    people: dict[str, list] = defaultdict(lambda: [0, 0.0, ""])
    for meeting in meetings:
        duration = _hours(meeting)
        seen: set[str] = set()
        for participant in meeting.participants:
            key, label = _person_key(participant.name, participant.email)
            if key in seen:
                continue
            seen.add(key)
            people[key][0] += 1
            people[key][1] += duration
            people[key][2] = people[key][2] or label

    owner_ids = {meeting.owner_id for meeting in meetings if meeting.owner_id}
    owners: dict[str, User] = {}
    if owner_ids:
        rows = await session.scalars(select(User).where(User.id.in_(owner_ids)))
        owners = {user.id: user for user in rows}

    by_owner: dict[str, list] = defaultdict(lambda: [0, 0.0, ""])
    for meeting in meetings:
        if not meeting.owner_id:
            continue
        user = owners.get(meeting.owner_id)
        label = (user.email or user.name or user.id) if user else meeting.owner_id
        bucket = by_owner[meeting.owner_id]
        bucket[0] += 1
        bucket[1] += _hours(meeting)
        bucket[2] = label

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        [
            "section",
            "week",
            "range_start",
            "range_end",
            "meetings",
            "total_hours",
            "previous_week",
            "previous_meetings",
            "previous_total_hours",
            "meetings_change",
            "hours_change",
        ]
    )
    writer.writerow(
        [
            "summary",
            week,
            start.isoformat(),
            end.isoformat(),
            count,
            f"{hours:.2f}",
            previous,
            previous_count,
            f"{previous_hours:.2f}",
            count - previous_count,
            f"{hours - previous_hours:.2f}",
        ]
    )
    writer.writerow([])
    writer.writerow(["section", "rank", "title", "start", "duration_hours", "participants"])
    for rank, meeting in enumerate(longest, start=1):
        writer.writerow(
            [
                "longest",
                rank,
                meeting.name,
                meeting.starts_at.isoformat(),
                f"{_hours(meeting):.2f}",
                len(meeting.participants),
            ]
        )
    writer.writerow([])
    writer.writerow(["section", "person", "meetings", "total_hours"])
    ranked_people = sorted(people.items(), key=lambda item: (-item[1][1], item[1][2]))
    for _key, (person_count, person_hours, label) in ranked_people:
        writer.writerow(["person", label, person_count, f"{person_hours:.2f}"])
    writer.writerow([])
    writer.writerow(["section", "owner", "meetings", "total_hours"])
    ranked_owners = sorted(by_owner.items(), key=lambda item: (-item[1][1], item[1][2]))
    for _key, (owner_count, owner_hours, label) in ranked_owners:
        writer.writerow(["owner", label, owner_count, f"{owner_hours:.2f}"])
    return buffer.getvalue().encode("utf-8")


async def _render(week: str) -> bytes:
    """Open a short-lived engine so a second Lambda invoke is not tied to a closed loop."""
    engine = make_engine()
    try:
        factory = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)
        async with factory() as session:
            return await render_weekly_report(session, week)
    finally:
        await engine.dispose()


def build_weekly_report(week: str) -> bytes:
    """Query the meetings of one ISO week (for example ``2026-W40``) and return the CSV."""
    return asyncio.run(_render(normalize_week(week)))
