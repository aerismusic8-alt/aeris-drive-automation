#!/usr/bin/env python3
"""PC1 side of the AX -> PC1 reverse control channel.

PC1 is behind NAT and off the agent's network, so the agent cannot dial in. This
runs on PC1, polls the rendezvous the agent hosts, executes whatever MCP tool
call it finds through the local winremote server, and posts the result back.
Every connection is outbound, so no port forward, no tunnel, and no inbound
rule on the Windows machine.

It carries winremote tool calls, so the agent gets screen capture, PowerShell,
file transfer and GUI input: everything the MCP server can do, with nobody
sitting at the machine.

Run once to install and verify:

  python ax-pc1-worker.py --rendezvous https://<host>/ --token <token> --once

Run continuously (normally installed as a scheduled task):

  python ax-pc1-worker.py --rendezvous https://<host>/ --token <token>

Uses urllib for the channel so the only third-party dependency is the MCP client
the winremote package already installs.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import platform
import socket
import sys
import time
import traceback
import urllib.error
import urllib.request

LOG_PATH = os.path.join(os.environ.get("TEMP", "."), "ax-pc1-worker.log")
# Where the watchdog reads "is the poll loop still turning?". The heartbeat is a
# timestamp rewritten every cycle, so its age is the whole signal: a worker that
# is wedged inside a tool call stops touching it, and a watchdog can tell that
# from a worker that is simply idle.
HEARTBEAT_PATH = os.path.join(
    os.environ.get("AX_RUNTIME", r"C:\AX-Runtime"), "evidence", "reverse-control-heartbeat.json"
)
# A tool call that outlives this is abandoned. The winremote Shell tool kills a
# command at 30s, so anything near this is already broken; without a cap one hung
# call stops the poll loop forever and every later job is dequeued and dropped,
# which is exactly how jobs 67 and 68 went missing on 2026-10-21.
DEFAULT_JOB_TIMEOUT = float(os.environ.get("AX_JOB_TIMEOUT", "120"))
# The effective cap, set by main() once the config is read. Module level so
# write_heartbeat can publish it without threading it through every call.
job_timeout_seconds = DEFAULT_JOB_TIMEOUT


def write_heartbeat(state: str, job_id: str | None = None) -> None:
    """Record that the loop is alive, and what it is doing right now.

    jobTimeout is published so the watchdog can tell a long job from a wedged
    loop. The heartbeat is only rewritten between jobs, so a healthy worker
    inside a slow tool call looks silent for as long as that call runs. The
    watchdog needs the cap to know how long silence is still legitimate, and
    reading it from here keeps the two numbers from drifting apart.
    """
    payload = {
        "protocol": "AX PC1 REVERSE CONTROL v1",
        "nodeId": "PC1",
        "computerName": socket.gethostname(),
        "state": state,
        "jobId": job_id,
        "jobTimeout": job_timeout_seconds,
        "heartbeatAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "pid": os.getpid(),
    }
    try:
        os.makedirs(os.path.dirname(HEARTBEAT_PATH), exist_ok=True)
        with open(HEARTBEAT_PATH, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
    except OSError as exc:
        log(f"heartbeat write failed: {type(exc).__name__}: {exc}")


def log(message: str) -> None:
    line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}"
    try:
        print(line, flush=True)
    except Exception:  # noqa: BLE001
        pass
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


class Channel:
    """Tiny HTTP client for the rendezvous.

    urllib rather than a third-party client: this must keep working on a machine
    whose Python environment we do not fully control, and the only thing it has
    to do is GET a job and POST a result.
    """

    def __init__(self, base: str, token: str, timeout: float = 30.0):
        self.base = base.rstrip("/") + "/"
        self.token = token
        self.timeout = timeout

    def _request(self, method: str, path: str, payload: dict | None = None) -> dict:
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("X-AX-Token", self.token)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
        return json.loads(raw) if raw else {}

    def next_job(self) -> dict | None:
        return (self._request("GET", "ax/jobs") or {}).get("job")

    def post(self, payload: dict) -> None:
        self._request("POST", "ax/result", payload)


def _identity() -> dict:
    return {
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python": sys.version.split()[0],
        "user": os.environ.get("USERNAME") or os.environ.get("USER"),
    }


def _render(content) -> list[dict]:
    """Flatten MCP content blocks, keeping images as base64.

    A screenshot has to come back as bytes the agent can look at, not as a byte
    count, or the agent is driving a machine it cannot see.
    """
    out: list[dict] = []
    for item in content or []:
        kind = getattr(item, "type", None)
        if kind == "text":
            out.append({"type": "text", "text": getattr(item, "text", "") or ""})
        elif kind == "image":
            data = getattr(item, "data", "") or ""
            out.append({
                "type": "image",
                "mimeType": getattr(item, "mimeType", None) or getattr(item, "mime_type", None),
                "base64Length": len(data),
                "data": data,
            })
        else:
            out.append({"type": str(kind), "raw": str(item)[:2000]})
    return out


async def run_job(mcp_url: str, job: dict) -> dict:
    from fastmcp import Client

    tool = job.get("tool")
    args = job.get("args") or {}
    started = time.time()

    async with Client(mcp_url) as client:
        if tool in (None, "__list_tools__"):
            tools = await client.list_tools()
            return {
                "ok": True,
                "tool": "__list_tools__",
                "tools": [
                    {"name": t.name, "description": (t.description or "").split("\n")[0][:200]}
                    for t in tools
                ],
            }

        result = await client.call_tool(tool, args, raise_on_error=False)
        return {
            "ok": not bool(getattr(result, "is_error", False) or getattr(result, "isError", False)),
            "tool": tool,
            "content": _render(getattr(result, "content", None)),
            "durationMs": int((time.time() - started) * 1000),
        }


def load_config(path: str | None) -> dict:
    """Read settings from a JSON file.

    The token lives here rather than on the task's command line, because a
    command line is visible to every process on the machine and this token is
    the only thing standing between the agent and arbitrary code execution.
    """
    if not path:
        return {}
    # utf-8-sig, not utf-8: Windows PowerShell 5.1 writes UTF8 with a byte order
    # mark, and json.load rejects a leading BOM outright. Reading it here means
    # the file can be written by either PowerShell version.
    with open(path, encoding="utf-8-sig") as fh:
        data = json.load(fh)
    return data if isinstance(data, dict) else {}


def main() -> int:
    parser = argparse.ArgumentParser(description="PC1 worker for the AX reverse channel")
    parser.add_argument("--config", help="JSON file with rendezvous/token/mcpUrl/poll")
    parser.add_argument("--rendezvous", help="Base URL of the rendezvous, e.g. https://host/")
    parser.add_argument("--token", default=os.environ.get("AX_TOKEN"))
    parser.add_argument("--mcp-url", default=os.environ.get("WINREMOTE_MCP_URL"))
    parser.add_argument("--poll", type=float, default=None, help="Seconds between polls")
    parser.add_argument(
        "--job-timeout",
        type=float,
        default=None,
        help="Seconds a single tool call may run before it is abandoned",
    )
    parser.add_argument("--once", action="store_true", help="One poll cycle then exit")
    args = parser.parse_args()

    cfg = load_config(args.config)
    rendezvous = args.rendezvous or cfg.get("rendezvous")
    token = args.token or cfg.get("token")
    mcp_url = args.mcp_url or cfg.get("mcpUrl") or "http://127.0.0.1:8090/mcp"
    poll = args.poll if args.poll is not None else float(cfg.get("poll") or 3.0)
    job_timeout = (
        args.job_timeout
        if args.job_timeout is not None
        else float(cfg.get("jobTimeout") or DEFAULT_JOB_TIMEOUT)
    )
    global job_timeout_seconds
    job_timeout_seconds = job_timeout

    if not rendezvous:
        log("FATAL no --rendezvous and none in config")
        return 2
    if not token:
        log("FATAL no --token and none in config")
        return 2

    channel = Channel(rendezvous, token)
    log(f"worker starting rendezvous={rendezvous} mcp={mcp_url}")

    hello = {"id": "hello", "type": "hello", "at": time.time(), **_identity()}
    try:
        channel.post(hello)
        log(f"hello sent: {hello['hostname']}")
    except Exception as exc:  # noqa: BLE001
        log(f"hello failed: {type(exc).__name__}: {exc}")
        if args.once:
            return 1

    while True:
        write_heartbeat("polling")
        try:
            job = channel.next_job()
        except Exception as exc:  # noqa: BLE001
            log(f"poll failed: {type(exc).__name__}: {exc}")
            job = None

        if job:
            job_id = job.get("id", "unknown")
            log(f"job {job_id} tool={job.get('tool')}")
            write_heartbeat("running", job_id)
            try:
                outcome = asyncio.run(asyncio.wait_for(run_job(mcp_url, job), job_timeout))
            except asyncio.TimeoutError:
                outcome = {
                    "ok": False,
                    "tool": job.get("tool"),
                    "error": f"JobTimeout: tool did not return within {job_timeout:.0f}s",
                }
                log(f"job {job_id} TIMEOUT after {job_timeout:.0f}s")
            except Exception as exc:  # noqa: BLE001 - report, never die
                outcome = {
                    "ok": False,
                    "tool": job.get("tool"),
                    "error": f"{type(exc).__name__}: {exc}",
                    "trace": traceback.format_exc()[-1500:],
                }
            payload = {"id": job_id, "type": "result", "at": time.time(), **outcome}
            try:
                channel.post(payload)
                log(f"result {job_id} ok={payload.get('ok')}")
            except Exception as exc:  # noqa: BLE001
                log(f"post failed for {job_id}: {type(exc).__name__}: {exc}")
            write_heartbeat("polling")

        if args.once:
            return 0
        time.sleep(max(0.5, poll))


if __name__ == "__main__":
    sys.exit(main())
