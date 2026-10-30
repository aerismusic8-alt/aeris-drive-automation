#!/usr/bin/env bash
# Serve the PC1 fix files on this sandbox's public URL so they can be pulled
# onto PC1 with one `iwr` command. The pod's URL is per-pod and dies with the
# pod, so this is a transport, not storage: the durable copy is the repo file
# ops/pc1_fix_remote.ps1 (packed into the AX knowledge vault).
#
#   bash ops/pc1_serve_fix.sh
#
# Prints the URL to give to K. Port 12000 maps to
# https://work-1-<pod-host>.prod-runtime.all-hands.dev/ .
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p /tmp/axpub
cp ops/pc1_fix_remote.ps1 ops/check_pc1.py ops/PC1-FIX-TH.md /tmp/axpub/
pkill -f "http.server 12000" 2>/dev/null || true
sleep 1
cd /tmp/axpub
nohup python3 -m http.server 12000 --bind 0.0.0.0 >/tmp/axpub.log 2>&1 &
sleep 2
# The public work-host name is NOT the pod hostname (that is the k8s pod, e.g.
# runtime-<id>-<hash>-<hash>). The work host is the one in the session's
# work_hosts block. Override with AX_WORK_HOST when it changes.
HOST="${AX_WORK_HOST:-work-1-jhakqeqvkcqlwmjh}"
BASE="https://${HOST}.prod-runtime.all-hands.dev"
echo "serving on port 12000"
echo "URL: ${BASE}/pc1_fix_remote.ps1"
curl -s -m 10 -o /dev/null -w "self-check: %{http_code}\n" "${BASE}/pc1_fix_remote.ps1" || true
