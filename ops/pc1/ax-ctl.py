#!/usr/bin/env python3
"""Agent side of the AX <-> PC1 reverse control channel.

Queues a winremote MCP tool call for PC1 and waits for the result. This is the
side the agent runs, so the two verbs it needs are "do this" and "show me what
came back", including the screenshots.

  python3 ax-ctl.py state
  python3 ax-ctl.py tools
  python3 ax-ctl.py call GetSystemInfo
  python3 ax-ctl.py call Shell --args '{"command":"whoami"}'
  python3 ax-ctl.py call Snapshot --save-images ./shots
  python3 ax-ctl.py wait <job-id>

The rendezvous URL and token come from --rendezvous/--token, then from
AX_RENDEZVOUS/AX_TOKEN, then from ax-results/.ax-token for the token.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_RESULTS = os.path.join(HERE, "ax-results")


def _token(explicit: str | None) -> str | None:
    if explicit or os.environ.get("AX_TOKEN"):
        return explicit or os.environ.get("AX_TOKEN")
    path = os.path.join(DEFAULT_RESULTS, ".ax-token")
    if os.path.exists(path):
        return open(path, encoding="utf-8").read().strip()
    return None


class Client:
    def __init__(self, base: str, token: str, timeout: float = 60.0):
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

    def state(self) -> dict:
        return self._request("GET", "ax/state")

    def enqueue(self, tool: str, args: dict | None = None) -> dict:
        return self._request("POST", "ax/enqueue", {"tool": tool, "args": args or {}})

    def wait(self, job_id: str, seconds: float) -> dict | None:
        deadline = time.time() + seconds
        while time.time() < deadline:
            hit = self.state().get("results", {}).get(job_id)
            if hit:
                return hit
            time.sleep(0.25)
        return None


def show_result(result: dict, save_images: str | None) -> int:
    ok = result.get("ok")
    print(f"job={result.get('id')} tool={result.get('tool')} ok={ok} {result.get('durationMs','')}ms")
    if result.get("error"):
        print(f"error: {result['error']}")
    if result.get("trace"):
        print(result["trace"])
    if result.get("tools"):
        for t in result["tools"]:
            print(f"  {t['name']}")
        return 0 if ok else 1

    if save_images:
        os.makedirs(save_images, exist_ok=True)
    for item in result.get("content", []):
        if item.get("type") == "text":
            print(item.get("text", ""))
        elif item.get("type") == "image":
            data = item.get("data") or ""
            if save_images and data:
                raw = base64.b64decode(data)
                path = os.path.join(save_images, f"{result.get('id')}.png")
                with open(path, "wb") as fh:
                    fh.write(raw)
                print(f"[image saved {path} {len(raw)} bytes]")
            else:
                print(f"[image {item.get('base64Length')} base64 chars]")
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Drive PC1 through the reverse channel")
    parser.add_argument("verb", choices=["state", "tools", "call", "wait"])
    parser.add_argument("tool", nargs="?")
    parser.add_argument("--args", help="JSON object of tool arguments")
    parser.add_argument("--rendezvous", default=os.environ.get("AX_RENDEZVOUS"))
    parser.add_argument("--token")
    parser.add_argument("--timeout", type=float, default=90.0, help="Seconds to wait for a result")
    parser.add_argument("--save-images", help="Directory to write returned PNGs into")
    args = parser.parse_args()

    if not args.rendezvous:
        print("need --rendezvous or AX_RENDEZVOUS", file=sys.stderr)
        return 2
    token = _token(args.token)
    if not token:
        print("no token: pass --token, set AX_TOKEN, or run the rendezvous once", file=sys.stderr)
        return 2

    client = Client(args.rendezvous, token)

    if args.verb == "state":
        st = client.state()
        hello = st.get("hello") or {}
        print(f"hello: {hello.get('hostname') or '(none yet)'} user={hello.get('user')} at={hello.get('at')}")
        print(f"queued: {len(st.get('queued', []))}")
        for jid, res in st.get("results", {}).items():
            print(f"  {jid}: tool={res.get('tool')} ok={res.get('ok')}")
        return 0

    if args.verb == "tools":
        args.tool = "__list_tools__"

    if args.verb in ("tools", "call"):
        if not args.tool:
            print("need a tool name", file=sys.stderr)
            return 2
        try:
            tool_args = json.loads(args.args) if args.args else {}
        except ValueError as exc:
            print(f"--args is not valid JSON: {exc}", file=sys.stderr)
            return 2
        job = client.enqueue(args.tool, tool_args)["job"]
        print(f"queued {job['id']} tool={job['tool']}")
        job_id = job["id"]
    else:
        if not args.tool:
            print("need a job id", file=sys.stderr)
            return 2
        job_id = args.tool

    result = client.wait(job_id, args.timeout)
    if not result:
        print(f"no result for {job_id} within {args.timeout}s", file=sys.stderr)
        return 1
    return show_result(result, args.save_images)


if __name__ == "__main__":
    sys.exit(main())
