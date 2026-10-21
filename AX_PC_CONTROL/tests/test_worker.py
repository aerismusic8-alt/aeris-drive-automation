"""The reverse-channel worker must not let one bad job stop the channel.

On 2026-10-21 jobs 67 and 68 were dequeued and never answered. The worker had
taken a job and then stopped polling, so the agent could not tell a busy channel
from a dead one. Two guards fix that, and both are tested here:

  * the worker writes a heartbeat every cycle, so "is it still turning?" has an
    answer that does not depend on a job finishing;
  * a tool call that outlives its timeout is abandoned and reported, so the loop
    always comes back to polling.
"""

import importlib.util
import json
import os
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_WORKER = Path(__file__).resolve().parents[1] / "ax-pc1-worker.py"
_spec = importlib.util.spec_from_file_location("ax_pc1_worker", _WORKER)
worker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(worker)


class _FakeRendezvous(BaseHTTPRequestHandler):
    """Serves one job, then nothing, and records what the worker posts back."""

    jobs = []
    results = []
    lock = threading.Lock()

    def log_message(self, fmt, *args):  # noqa: A003 - BaseHTTPRequestHandler API
        pass

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
        if self.path.startswith("/ax/jobs"):
            with self.lock:
                job = self.jobs.pop(0) if self.jobs else None
            self._send({"job": job})
        else:
            self._send({})

    def do_POST(self):  # noqa: N802 - BaseHTTPRequestHandler API
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        with self.lock:
            self.results.append(body)
        self._send({"ok": True})

    def _send(self, payload):
        raw = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self._old_heartbeat = worker.HEARTBEAT_PATH
        worker.HEARTBEAT_PATH = os.path.join(self.tmp.name, "reverse-control-heartbeat.json")
        self.addCleanup(self._restore_heartbeat)
        _FakeRendezvous.jobs = []
        _FakeRendezvous.results = []

    def _restore_heartbeat(self):
        worker.HEARTBEAT_PATH = self._old_heartbeat

    def test_heartbeat_is_written_and_readable(self):
        worker.write_heartbeat("polling")
        with open(worker.HEARTBEAT_PATH, encoding="utf-8") as fh:
            hb = json.load(fh)
        self.assertEqual(hb["state"], "polling")
        self.assertEqual(hb["nodeId"], "PC1")
        # The watchdog parses this field, so it has to be a UTC instant it can read.
        self.assertTrue(hb["heartbeatAt"].endswith("Z"))
        parsed = time.strptime(hb["heartbeatAt"], "%Y-%m-%dT%H:%M:%SZ")
        self.assertGreater(time.mktime(parsed), 0)

    def test_heartbeat_records_the_job_being_run(self):
        worker.write_heartbeat("running", "job-000042")
        with open(worker.HEARTBEAT_PATH, encoding="utf-8") as fh:
            hb = json.load(fh)
        self.assertEqual(hb["state"], "running")
        self.assertEqual(hb["jobId"], "job-000042")

    def test_heartbeat_publishes_the_job_timeout(self):
        """The watchdog derives its stale threshold from this value.

        The heartbeat is only rewritten between jobs, so a healthy worker inside
        a slow tool call is silent for as long as that call runs. If the worker
        does not publish its cap, the watchdog falls back to a fixed floor and
        can restart a worker that is mid-call.
        """
        old = worker.job_timeout_seconds
        self.addCleanup(setattr, worker, "job_timeout_seconds", old)

        worker.job_timeout_seconds = 300
        worker.write_heartbeat("running", "job-000043")
        with open(worker.HEARTBEAT_PATH, encoding="utf-8") as fh:
            hb = json.load(fh)
        self.assertEqual(hb["jobTimeout"], 300)

    def test_heartbeat_is_utc_not_local_time(self):
        """A local-time stamp mislabelled as UTC makes the watchdog restart forever.

        PC1 runs at UTC+7. If the worker wrote local time and called it UTC, the
        watchdog would compute a seven-hour age and restart a perfectly healthy
        channel every poll. The test forces a non-UTC zone so this cannot pass by
        accident on a machine that happens to run on UTC.
        """
        old_tz = os.environ.get("TZ")
        os.environ["TZ"] = "Asia/Bangkok"
        time.tzset()
        self.addCleanup(self._restore_tz, old_tz)

        worker.write_heartbeat("polling")
        with open(worker.HEARTBEAT_PATH, encoding="utf-8") as fh:
            hb = json.load(fh)

        stamped = time.mktime(time.strptime(hb["heartbeatAt"], "%Y-%m-%dT%H:%M:%SZ"))
        drift = abs(stamped - time.mktime(time.gmtime()))
        self.assertLess(drift, 60, f"heartbeat is not UTC: {hb['heartbeatAt']}")

    def _restore_tz(self, old_tz):
        if old_tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = old_tz
        time.tzset()

    def test_a_hung_job_times_out_and_the_loop_reports_it(self):
        """The regression: a job that never returns must not stop the channel."""
        server = ThreadingHTTPServer(("127.0.0.1", 0), _FakeRendezvous)
        self.addCleanup(server.server_close)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        port = server.server_address[1]

        _FakeRendezvous.jobs = [{"id": "job-hang", "tool": "Shell", "args": {"command": "sleep"}}]

        async def never_returns(_mcp_url, _job):
            import asyncio

            await asyncio.sleep(30)

        old_run_job = worker.run_job
        worker.run_job = never_returns
        self.addCleanup(setattr, worker, "run_job", old_run_job)

        import sys

        argv = sys.argv
        sys.argv = [
            "ax-pc1-worker.py",
            "--rendezvous", f"http://127.0.0.1:{port}/",
            "--token", "test-token",
            "--job-timeout", "1",
            "--once",
        ]
        self.addCleanup(setattr, sys, "argv", argv)

        started = time.time()
        rc = worker.main()
        elapsed = time.time() - started

        self.assertEqual(rc, 0)
        # It gave up on the job instead of waiting it out.
        self.assertLess(elapsed, 10)
        with _FakeRendezvous.lock:
            results = list(_FakeRendezvous.results)
        outcome = [r for r in results if r.get("id") == "job-hang"]
        self.assertEqual(len(outcome), 1, results)
        self.assertFalse(outcome[0]["ok"])
        self.assertIn("JobTimeout", outcome[0]["error"])


if __name__ == "__main__":
    unittest.main()
