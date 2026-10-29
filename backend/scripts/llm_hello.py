"""Part 1 / Step 1: Converse to Claude + Nova from the laptop."""

from __future__ import annotations

import json
import os
import sys

import boto3


def main() -> int:
    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "eu-north-1"
    # Inference-profile id required on this account (foundation model id alone fails).
    model = os.environ.get("PARSER_MODEL", "eu.anthropic.claude-sonnet-4-6")
    question = "In one sentence: what is an ISO week?"
    brt = boto3.client("bedrock-runtime", region_name=region)

    print(f"region={region} model={model}")
    print("--- Converse API (Claude) ---")
    resp = brt.converse(
        modelId=model,
        messages=[{"role": "user", "content": [{"text": question}]}],
        inferenceConfig={"maxTokens": 200},
    )
    text = resp["output"]["message"]["content"][0]["text"]
    print(text)
    print(f"stop_reason={resp.get('stopReason')} usage={resp['usage']}")

    print("--- Converse API (Nova Micro) ---")
    for nova in ("eu.amazon.nova-micro-v1:0", "amazon.nova-micro-v1:0"):
        try:
            nova_resp = brt.converse(
                modelId=nova,
                messages=[{"role": "user", "content": [{"text": question}]}],
                inferenceConfig={"maxTokens": 200},
            )
            print(nova_resp["output"]["message"]["content"][0]["text"])
            print(json.dumps(nova_resp["usage"], default=str))
            break
        except Exception as exc:
            print(f"{nova} failed: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
