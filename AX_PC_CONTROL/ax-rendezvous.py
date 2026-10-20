#!/usr/bin/env python3
"""Rendezvous endpoint for the AX -> PC1 reverse control channel.

PC1 sits behind NAT, so an agent on the outside cannot dial in: no inbound port,
and the machine is not on a network the agent shares. Instead PC1 polls this
endpoint from the inside and picks up work. The connection is always outbound,
which needs no port forward, no tunnel and no new credential on the Windows
side.

The channel carries winremote MCP tool calls, so whatever the MCP server can do
on PC1 (screen capture, PowerShell, files, GUI input) the agent can do, without
anyone sitting at the machine.

Endpoints (all need the token except /ax/health):

  GET  /ax/health     liveness, no auth, so a monitor can watch it
  GET  /ax/jobs       PC1: take the next queued job
  POST /ax/result     PC1: post the result of a job
  POST /ax/enqueue    AX: queue a job
  GET  /ax/state      AX: inspect the queue, the last hello and all results

Token comes from --token or AX_TOKEN. If neither is set one is generated and
written next to this script, because an unauthenticated endpoint that can run
PowerShell on someone's machine is not something to leave open by accident.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LOCK = threading.Lock()
JOBS: deque = deque()
RESULTS: dict = {}
HELLO: dict = {}
COUNTER = [0]
RESULTS_DIR = ""


def _new_id() -> str:
    COUNTER[0] += 1
    return f"job-{COUNTER[0]:06d}"


def _persist(job_id: str, payload: dict) -> None:
    """Write each result to disk as it arrives.

    Results are the whole point of the exercise, so they survive a restart of
    this process rather than living only in memory.
    """
    if not RESULTS_DIR:
        return
    try:
        os.makedirs(RESULTS_DIR, exist_ok=True)
        with open(os.path.join(RESULTS_DIR, f"{job_id}.json"), "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False)
    except OSError as exc:
        sys.stderr.write(f"persist failed for {job_id}: {exc}\n")


class Handler(BaseHTTPRequestHandler):
    token = ""
    server_version = "ax-rendezvous/1"

    def log_message(self, fmt, *args):  # noqa: A003 - BaseHTTPRequestHandler API
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _authed(self, query: dict) -> bool:
        given = self.headers.get("X-AX-Token") or (query.get("token") or [None])[0]
        return bool(given) and secrets.compare_digest(given, self.token)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            parsed = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}
        return parsed if isinstance(parsed, dict) else {}

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
        url = urlparse(self.path)
        query = parse_qs(url.query)

        if url.path == "/ax/health":
            with LOCK:
                self._send(200, {"ok": True, "queued": len(JOBS), "results": len(RESULTS)})
            return

        if not self._authed(query):
            self._send(401, {"error": "unauthorized"})
            return

        if url.path == "/ax/jobs":
            with LOCK:
                job = JOBS.popleft() if JOBS else None
            self._send(200, {"job": job})
            return

        if url.path == "/ax/state":
            with LOCK:
                self._send(200, {
                    "hello": HELLO,
                    "queued": list(JOBS),
                    "results": RESULTS,
                })
            return

        self._send(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802 - BaseHTTPRequestHandler API
        url = urlparse(self.path)
        query = parse_qs(url.query)

        if not self._authed(query):
            self._send(401, {"error": "unauthorized"})
            return

        body = self._read_json()

        if url.path == "/ax/enqueue":
            job = {
                "id": _new_id(),
                "tool": body.get("tool"),
                "args": body.get("args") or {},
                "note": body.get("note"),
                "createdAt": time.time(),
            }
            with LOCK:
                JOBS.append(job)
            self._send(200, {"job": job})
            return

        if url.path == "/ax/result":
            job_id = str(body.get("id") or "unknown")
            with LOCK:
                RESULTS[job_id] = body
                if body.get("type") == "hello":
                    HELLO.update(body)
            _persist(job_id, body)
            self._send(200, {"ok": True})
            return

        self._send(404, {"error": "not found"})


def main() -> int:
    global RESULTS_DIR

    parser = argparse.ArgumentParser(description="AX <-> PC1 rendezvous")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=12000)
    parser.add_argument("--token", default=os.environ.get("AX_TOKEN"))
    parser.add_argument("--results-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "ax-results"))
    args = parser.parse_args()

    RESULTS_DIR = args.results_dir
    os.makedirs(RESULTS_DIR, exist_ok=True)

    token = args.token
    if not token:
        token_file = os.path.join(RESULTS_DIR, ".ax-token")
        if os.path.exists(token_file):
            token = open(token_file, encoding="utf-8").read().strip()
        if not token:
            token = secrets.token_urlsafe(32)
            with open(token_file, "w", encoding="utf-8") as fh:
                fh.write(token)

    Handler.token = token
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    sys.stderr.write(f"rendezvous listening on {args.host}:{args.port}\n")
    sys.stderr.write(f"results dir: {RESULTS_DIR}\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
