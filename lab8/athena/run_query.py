#!/usr/bin/env python3
"""Run an Athena SQL file in eu-north-1 and print status, scan stats, preview."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import boto3

REGION = "eu-north-1"
OUTPUT = "s3://successfulsuccess-lab8-payments-378600555796/athena-results/"
DB = "lab8"
WG = "primary"


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: run_query.py file.sql [database]", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    database = sys.argv[2] if len(sys.argv) > 2 else DB
    sql = path.read_text()

    client = boto3.Session(profile_name="spry", region_name=REGION).client("athena")
    qid = client.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": database} if database else {},
        ResultConfiguration={"OutputLocation": OUTPUT},
        WorkGroup=WG,
    )["QueryExecutionId"]
    print(f"=== {path.name} qid={qid}")

    while True:
        qe = client.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        state = qe["Status"]["State"]
        if state in {"SUCCEEDED", "FAILED", "CANCELLED"}:
            break
        time.sleep(2)

    stats = qe.get("Statistics", {})
    print("state=", state)
    if qe["Status"].get("StateChangeReason"):
        print("reason=", qe["Status"]["StateChangeReason"][:800])
    print("data_scanned_bytes=", stats.get("DataScannedInBytes"))
    print("engine_ms=", stats.get("EngineExecutionTimeInMillis"))
    print("total_ms=", stats.get("TotalExecutionTimeInMillis"))

    out = {
        "file": path.name,
        "qid": qid,
        "state": state,
        "data_scanned_bytes": stats.get("DataScannedInBytes"),
        "engine_ms": stats.get("EngineExecutionTimeInMillis"),
        "total_ms": stats.get("TotalExecutionTimeInMillis"),
        "reason": qe["Status"].get("StateChangeReason"),
    }
    Path(path.with_suffix(".meta.json")).write_text(json.dumps(out, indent=2) + "\n")

    if state != "SUCCEEDED":
        return 1

    results = client.get_query_results(QueryExecutionId=qid, MaxResults=30)
    rows = results["ResultSet"]["Rows"]
    preview_path = path.with_suffix(".preview.txt")
    lines = []
    for row in rows:
        line = " | ".join(d.get("VarCharValue", "") for d in row["Data"])
        lines.append(line)
        print(line)
    preview_path.write_text("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
