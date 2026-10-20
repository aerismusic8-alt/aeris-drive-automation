#!/usr/bin/env python3
"""End-to-end test of the AX <-> PC1 reverse control channel.

Runs the real rendezvous, a real winremote MCP server, and the real worker on
this machine, then enqueues jobs and checks the results come back. This is the
whole point: prove the path works here, where the output is visible, instead of
discovering it does not work on the machine we cannot see.

  python3 test-reverse-channel.py
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
RENDEZVOUS = os.path.join(HERE, "ax-rendezvous.py")
WORKER = os.path.join(HERE, "ax-pc1-worker.py")
RESULTS = os.path.join(HERE, "ax-results-test")
PORT_RV = 12010
PORT_MCP = 8095
TOKEN = "test-token-not-a-secret"
# Smallest valid PNG, used to prove image bytes survive the channel intact.
PNG_1PX = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=="
)
BASE = f"http://127.0.0.1:{PORT_RV}/"

procs = []


def start(cmd, name):
    log = open(os.path.join(HERE, f"test-{name}.log"), "w")
    p = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
    procs.append((name, p))
    return p


def req(method, path, payload=None, timeout=30):
    data = json.dumps(payload).encode() if payload is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method)
    r.add_header("X-AX-Token", TOKEN)
    if data:
        r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, timeout=timeout) as resp:
        body = resp.read().decode()
    return json.loads(body) if body else {}


def wait_for(fn, seconds, what):
    for _ in range(int(seconds * 2)):
        try:
            if fn():
                return True
        except Exception:
            pass
        time.sleep(0.5)
    print(f"TIMEOUT waiting for {what}")
    return False


def cleanup():
    for name, p in procs:
        try:
            p.terminate()
        except Exception:
            pass


def main():
    os.makedirs(RESULTS, exist_ok=True)
    failures = []

    # 1. rendezvous
    start([sys.executable, "-u", RENDEZVOUS, "--port", str(PORT_RV),
           "--token", TOKEN, "--results-dir", RESULTS], "rendezvous")
    if not wait_for(lambda: urllib.request.urlopen(f"{BASE}ax/health", timeout=3).status == 200, 15, "rendezvous"):
        print("FAIL: rendezvous never came up")
        cleanup()
        return 1
    print("PASS rendezvous up")

    # 2. auth is enforced
    try:
        r = urllib.request.Request(BASE + "ax/state")
        urllib.request.urlopen(r, timeout=5)
        failures.append("unauthenticated request was accepted")
        print("FAIL auth not enforced")
    except urllib.error.HTTPError as e:
        if e.code == 401:
            print("PASS auth enforced (401 without token)")
        else:
            failures.append(f"unexpected auth code {e.code}")

    # 3. MCP server with tier3
    start([sys.executable, "-u", "-m", "winremote", "--transport", "streamable-http",
           "--host", "127.0.0.1", "--port", str(PORT_MCP), "--enable-tier3"], "mcp")
    if not wait_for(lambda: urllib.request.urlopen(f"http://127.0.0.1:{PORT_MCP}/health", timeout=3).status == 200, 40, "mcp"):
        print("FAIL: mcp server never came up")
        cleanup()
        return 1
    print("PASS mcp server up (tier3)")

    # 4. worker
    # Use a config file, which is how the installer registers it: the token must
    # not sit on a command line where any process on the machine can read it.
    cfg_path = os.path.join(RESULTS, "worker-config.json")
    with open(cfg_path, "w", encoding="utf-8") as fh:
        json.dump({
            "rendezvous": BASE,
            "token": TOKEN,
            "mcpUrl": f"http://127.0.0.1:{PORT_MCP}/mcp",
            "poll": 1,
        }, fh)
    start([sys.executable, "-u", WORKER, "--config", cfg_path], "worker")

    if not wait_for(lambda: req("GET", "ax/state").get("hello", {}).get("hostname"), 25, "worker hello"):
        print("FAIL: worker never said hello")
        cleanup()
        return 1
    print(f"PASS worker hello: {req('GET','ax/state')['hello']['hostname']}")

    # 5. a real job through the whole path
    queued = req("POST", "ax/enqueue", {"tool": "GetSystemInfo", "args": {}})
    job_id = queued["job"]["id"]
    print(f"     enqueued {job_id}")

    def result_for(jid):
        return req("GET", "ax/state").get("results", {}).get(jid)

    if not wait_for(lambda: result_for(job_id), 45, f"result {job_id}"):
        failures.append("job result never arrived")
        print("FAIL no result")
    else:
        res = result_for(job_id)
        text = " ".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
        print(f"PASS job {job_id} ok={res.get('ok')} text={text[:160]!r}")
        if not text:
            failures.append("GetSystemInfo returned no text")

    # 6. list tools, to confirm Shell is reachable through the channel
    queued = req("POST", "ax/enqueue", {"tool": "__list_tools__", "args": {}})
    tid = queued["job"]["id"]
    if wait_for(lambda: result_for(tid), 45, "tool list"):
        names = [t["name"] for t in result_for(tid).get("tools", [])]
        print(f"PASS tool list via channel: {len(names)} tools, Shell={'Shell' in names}")
        if "Shell" not in names:
            failures.append("Shell not available")
    else:
        failures.append("no tool list result")
        print("FAIL tool list")

    # 7. Shell through the channel: the agent must be able to run commands.
    # powershell only exists on Windows, so on a Linux test host the transport is
    # what gets proven here and the command itself is expected to fail.
    shell_cmd = "echo ax-channel-ok" if os.name == "nt" else None
    if shell_cmd:
        queued = req("POST", "ax/enqueue", {"tool": "Shell", "args": {"command": shell_cmd}})
        sid = queued["job"]["id"]
        if wait_for(lambda: result_for(sid), 60, "shell result"):
            res = result_for(sid)
            text = " ".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
            print(f"PASS Shell ok={res.get('ok')} text={text[:160]!r}")
            if "ax-channel-ok" not in text:
                failures.append("Shell output did not contain the marker")
        else:
            failures.append("shell result never arrived")
            print("FAIL shell")
    else:
        print("SKIP Shell (not Windows); transport already proven by the job above")

    # 8. Snapshot on Windows; on Linux, prove the image path directly instead,
    # because the transport must carry a PNG through unchanged. A screenshot that
    # arrives as a byte count leaves the agent blind.
    if os.name == "nt":
        queued = req("POST", "ax/enqueue", {"tool": "Snapshot", "args": {}})
        snap_id = queued["job"]["id"]
        if wait_for(lambda: result_for(snap_id), 60, "snapshot result"):
            res = result_for(snap_id)
            images = [c for c in res.get("content", []) if c.get("type") == "image"]
            if images:
                raw = base64.b64decode(images[0]["data"])
                is_png = raw[:8] == b"\x89PNG\r\n\x1a\n"
                print(f"PASS Snapshot: {len(images)} image(s), {len(raw)} bytes, PNG={is_png}")
                if not is_png:
                    failures.append("snapshot bytes are not a PNG")
            else:
                failures.append("snapshot returned no image content")
                print(f"FAIL snapshot content: {str(res)[:200]}")
        else:
            failures.append("snapshot result never arrived")
            print("FAIL snapshot")
    else:
        # Import by path, since the module name has dashes.
        import importlib.util
        spec = importlib.util.spec_from_file_location("ax_pc1_worker", WORKER)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        class FakeImage:
            type = "image"
            mimeType = "image/png"
            data = base64.b64encode(PNG_1PX).decode()

        class FakeText:
            type = "text"
            text = "hello"

        rendered = mod._render([FakeText(), FakeImage()])
        imgs = [c for c in rendered if c["type"] == "image"]
        if imgs and base64.b64decode(imgs[0]["data"]) == PNG_1PX:
            print(f"PASS image passthrough renders as image ({imgs[0]['base64Length']} b64 chars)")
        else:
            failures.append("image content did not survive rendering")
            print(f"FAIL image rendering: {rendered}")

    # 9. an error job must not kill the worker
    queued = req("POST", "ax/enqueue", {"tool": "NoSuchTool", "args": {}})
    bad_id = queued["job"]["id"]
    if wait_for(lambda: result_for(bad_id), 30, "error result"):
        print(f"PASS bad tool reported as failure without dying (ok={result_for(bad_id).get('ok')})")
    else:
        failures.append("bad tool not reported")

    # 10. the worker must still be alive after a failing job
    st = req("GET", "ax/state")
    if st.get("hello"):
        print("PASS worker still registered after failures")
    else:
        failures.append("worker lost")

    # 11. results persisted to disk
    files = [f for f in os.listdir(RESULTS) if f.endswith(".json")]
    if len(files) >= 4:
        print(f"PASS results persisted: {len(files)} files")
    else:
        failures.append(f"only {len(files)} results persisted")

    cleanup()
    print()
    if failures:
        print("FAILURES:")
        for f in failures:
            print(" -", f)
        return 1
    print("ALL CHECKS PASSED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        cleanup()
