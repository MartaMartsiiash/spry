"""On-demand weekly report. HTTP only: the service writes the request file."""

from fastapi import APIRouter, status

from app.auth import CurrentUserDep
from app.schemas.report import ReportAccepted, ReportRequest
from app.services.report_request import enqueue_report

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post(
    "",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=ReportAccepted,
    summary="Queue this week's report (or one ISO week) and return a receipt",
)
async def create_report(_user: CurrentUserDep, body: ReportRequest | None = None) -> ReportAccepted:
    # The dependency is what makes the button require sign-in. The file itself
    # does not name the caller: the builder does not care who asked.
    accepted = enqueue_report(None if body is None else body.week)
    return ReportAccepted.model_validate(accepted)
