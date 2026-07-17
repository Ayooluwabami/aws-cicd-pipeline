#!/usr/bin/env python3
"""Post-deploy verification: prove a release is actually serving.

Reads the stack outputs, polls the app's health endpoint until it responds,
checks the Prometheus endpoint, and prints the state of every pipeline stage.
Exits non-zero if anything is unhealthy, so it can gate other automation.

Stdlib only (uses the aws CLI via subprocess), no pip installs needed.

    platform/verify_deploy.py --stack cicd-demo --region us-east-1
"""

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request


def aws(args: list[str], region: str) -> dict:
    cmd = ["aws", *args, "--region", region, "--output", "json"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def stack_outputs(stack: str, region: str) -> dict[str, str]:
    data = aws(["cloudformation", "describe-stacks", "--stack-name", stack], region)
    outputs = data["Stacks"][0].get("Outputs", [])
    return {o["OutputKey"]: o["OutputValue"] for o in outputs}


def fetch(url: str, timeout: float = 5.0) -> tuple[int, str]:
    with urllib.request.urlopen(url, timeout=timeout) as res:
        return res.status, res.read().decode("utf-8", errors="replace")


def wait_for_health(base_url: str, deadline_s: int) -> dict:
    url = f"{base_url}/api/health"
    end = time.monotonic() + deadline_s
    last_err = "no attempt made"
    while time.monotonic() < end:
        try:
            status, body = fetch(url)
            if status == 200:
                return json.loads(body)
            last_err = f"HTTP {status}"
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            last_err = str(exc)
        time.sleep(5)
    raise SystemExit(f"FAIL: {url} not healthy within {deadline_s}s (last: {last_err})")


def check_metrics(base_url: str) -> None:
    status, body = fetch(f"{base_url}/metrics")
    if status != 200 or "http_request_duration_seconds_bucket" not in body:
        raise SystemExit("FAIL: /metrics missing the request histogram")
    print("ok    /metrics exposes the request latency histogram")


def pipeline_state(stack: str, region: str) -> bool:
    data = aws(["codepipeline", "get-pipeline-state", "--name", f"{stack}-pipeline"], region)
    all_green = True
    for stage in data["stageStates"]:
        status = stage.get("latestExecution", {}).get("status", "Unknown")
        marker = "ok   " if status == "Succeeded" else "WARN "
        if status != "Succeeded":
            all_green = False
        print(f"{marker} pipeline stage {stage['stageName']}: {status}")
    return all_green


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stack", default="cicd-demo")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--timeout", type=int, default=120, help="seconds to wait for health")
    args = parser.parse_args()

    outputs = stack_outputs(args.stack, args.region)
    app_url = outputs.get("ApplicationURL")
    if not app_url:
        raise SystemExit("FAIL: stack has no ApplicationURL output")
    print(f"ok    stack {args.stack} found, app at {app_url}")

    health = wait_for_health(app_url, args.timeout)
    print(f"ok    /api/health returned status={health['status']} uptime={health['uptime']:.0f}s")

    check_metrics(app_url)

    if not pipeline_state(args.stack, args.region):
        raise SystemExit("FAIL: not every pipeline stage is green")

    print("PASS: deployment verified")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"FAIL: aws cli error: {exc.stderr.strip()}")
