"""The report button's API: 202 and a request file, never a direct SQS call."""

import json
from unittest import mock

from botocore.exceptions import ClientError

from app.config import settings


async def test_request_report_returns_202_and_writes_requests_prefix(client, monkeypatch):
    monkeypatch.setattr(settings, "reports_bucket", "reports-bucket")
    put = mock.Mock()
    monkeypatch.setattr(
        "app.services.report_request.boto3.client",
        lambda _service: mock.Mock(put_object=put),
    )

    response = await client.post("/api/v1/reports", json={})

    assert response.status_code == 202, response.text
    body = response.json()
    assert body["status"] == "queued"
    assert body["week"].startswith("20")
    kwargs = put.call_args.kwargs
    assert kwargs["Bucket"] == "reports-bucket"
    assert kwargs["Key"].startswith("requests/")
    assert kwargs["Key"].endswith(".json")
    stored = json.loads(kwargs["Body"])
    assert stored == {"id": body["id"], "week": body["week"], "source": "api"}


async def test_request_report_without_a_bucket_is_503(client, monkeypatch):
    monkeypatch.setattr(settings, "reports_bucket", "")

    response = await client.post("/api/v1/reports", json={})

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "service_unavailable"


async def test_request_report_rejects_a_bad_week(client, monkeypatch):
    monkeypatch.setattr(settings, "reports_bucket", "reports-bucket")

    response = await client.post("/api/v1/reports", json={"week": "next-week"})

    assert response.status_code == 422


async def test_request_report_surfaces_a_storage_failure(client, monkeypatch):
    monkeypatch.setattr(settings, "reports_bucket", "reports-bucket")

    def client_factory(_service: str):
        def put_object(**_kwargs):
            raise ClientError({"Error": {"Code": "NoSuchBucket", "Message": "no"}}, "PutObject")

        return mock.Mock(put_object=put_object)

    monkeypatch.setattr("app.services.report_request.boto3.client", client_factory)

    response = await client.post("/api/v1/reports", json={"week": "2026-W40"})

    assert response.status_code == 503
    assert "queue" in response.json()["error"]["message"]
