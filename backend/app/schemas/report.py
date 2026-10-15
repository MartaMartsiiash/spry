"""Request and response for "send me this week's report"."""

from typing import Literal

from pydantic import BaseModel, field_validator

from app.reports.weekly import normalize_week


class ReportRequest(BaseModel):
    """An empty body, or ``{"week": "2026-W40"}`` to rebuild one week."""

    week: str | None = None

    @field_validator("week")
    @classmethod
    def _week(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        return normalize_week(value)


class ReportAccepted(BaseModel):
    """The receipt. The report is not built yet; 202 means the request was taken."""

    id: str
    week: str
    status: Literal["queued"]
