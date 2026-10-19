#!/usr/bin/env bash
# Dispatch the PC1 QR capture, fetch its artifact, and print the sign-in code.
#
# The code lives about two minutes, so this waits on the run it started rather
# than any older run, then decodes the frames as soon as they land.
#
# Usage: scripts/pc1-get-code.sh [branch]
set -uo pipefail

REPO=aerismusic8-alt/aeris-drive-automation
WF=ax-pc1-studio-login-qr.yml
BR=${1:-ax-pc1-studio-probe}

api() { python3 scripts/gh-api.py "$@" 2>/dev/null | tail -n +2; }
tok=$(node scripts/gh-app-token.mjs | head -1)

newest() {
  api GET "/repos/$REPO/actions/workflows/$WF/runs?per_page=30&event=workflow_dispatch" |
    python3 -c "import json,sys
runs=json.load(sys.stdin).get('workflow_runs',[])
print(max([r['id'] for r in runs]) if runs else '')"
}

prev=$(newest)
echo "[$(date -u +%H:%M:%S)] dispatch prev=$prev"
api POST "/repos/$REPO/actions/workflows/$WF/dispatches" --field "ref=$BR" >/dev/null

run=""
for _ in $(seq 1 60); do
  sleep 2
  cur=$(newest)
  if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then run=$cur; break; fi
done
echo "[$(date -u +%H:%M:%S)] run=$run"
[ -n "$run" ] || { echo NO_RUN; exit 1; }

art=""
for _ in $(seq 1 80); do
  sleep 2
  art=$(api GET "/repos/$REPO/actions/runs/$run/artifacts" |
    python3 -c "import json,sys;a=json.load(sys.stdin)['artifacts'];print(a[0]['id'] if a else '')" 2>/dev/null)
  [ -n "$art" ] && break
done
echo "[$(date -u +%H:%M:%S)] artifact=$art"
[ -n "$art" ] || { echo NO_ARTIFACT; exit 1; }

tmp=$(mktemp -d)
curl -sL -H "Authorization: Bearer $tok" -o "$tmp/a.zip" \
  "https://api.github.com/repos/$REPO/actions/artifacts/$art/zip"
python3 -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
  "$tmp/a.zip" "$tmp"
echo "[$(date -u +%H:%M:%S)] downloaded $(ls "$tmp" | tr '\n' ' ')"
python3 scripts/decode-studio-qr.py "$tmp"/*.png
echo "[$(date -u +%H:%M:%S)] done"
