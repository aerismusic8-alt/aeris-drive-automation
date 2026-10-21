#!/bin/bash
# Mutation checks for the reverse-channel worker.
#
# Each mutation reintroduces a bug and the suite must catch it. A test that
# passes on both the good and the broken code proves nothing, so the mutations
# are run rather than assumed. Usage: bash tests/mutate-worker.sh
set -u
cd "$(dirname "$0")/.." || exit 1
PY=python3
BAK=/tmp/ax-worker.bak
cp ax-pc1-worker.py "$BAK"
trap 'cp "$BAK" ax-pc1-worker.py' EXIT

count() { $PY -m unittest tests.test_worker 2>&1 | grep -cE "^(FAILED|OK)|Ran .* tests"; }
failures() { $PY -m unittest tests.test_worker 2>&1 | grep -oE "FAILED \(.*\)" | head -1; }
ran() { $PY -m unittest tests.test_worker 2>&1 | grep -E "^Ran " ; }
status() { $PY -m unittest tests.test_worker >/dev/null 2>&1 && echo "PASS" || echo "FAIL"; }

echo "=== baseline: expect PASS ==="
echo "$(status)"

echo "=== MUTATION 1: job timeout removed, so a hung job wedges the loop ==="
$PY - <<'PY'
p='ax-pc1-worker.py'; s=open(p).read()
s=s.replace("outcome = asyncio.run(asyncio.wait_for(run_job(mcp_url, job), job_timeout))",
            "outcome = asyncio.run(run_job(mcp_url, job))")
s=s.replace('''            except asyncio.TimeoutError:
                outcome = {
                    "ok": False,
                    "tool": job.get("tool"),
                    "error": f"JobTimeout: tool did not return within {job_timeout:.0f}s",
                }
                log(f"job {job_id} TIMEOUT after {job_timeout:.0f}s")
''','')
open(p,'w').write(s)
PY
echo "$(status)"
cp "$BAK" ax-pc1-worker.py

echo "=== MUTATION 2: heartbeat never written, so the watchdog sees a dead channel ==="
$PY - <<'PY'
p='ax-pc1-worker.py'; s=open(p).read()
s=s.replace('    payload = {\n        "protocol": "AX PC1 REVERSE CONTROL v1",',
            '    payload = {\n        "protocol": "AX PC1 REVERSE CONTROL v1",')
s=s.replace('        with open(HEARTBEAT_PATH, "w", encoding="utf-8") as fh:\n            json.dump(payload, fh)',
            '        with open(HEARTBEAT_PATH + ".unused", "w", encoding="utf-8") as fh:\n            json.dump(payload, fh)')
open(p,'w').write(s)
PY
echo "$(status)"
cp "$BAK" ax-pc1-worker.py

echo "=== MUTATION 3: heartbeat timestamp in local time, so age is wrong ==="
$PY - <<'PY'
p='ax-pc1-worker.py'; s=open(p).read()
s=s.replace('"heartbeatAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),',
            '"heartbeatAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.localtime()),')
open(p,'w').write(s)
PY
echo "$(status)"
cp "$BAK" ax-pc1-worker.py

echo "=== restored: expect PASS ==="
echo "$(status)"
