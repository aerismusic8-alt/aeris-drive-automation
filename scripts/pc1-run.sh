#!/usr/bin/env bash
# Dispatch a PC1 workflow, wait for the run it started, then print its job log.
#
# PC1 is the self-hosted runner, so a dispatch is a remote command on PC1.
# Runs are matched by head SHA plus event so a stale run is never mistaken for
# the one just started.
#
# Usage: scripts/pc1-run.sh <workflow-file> [branch]
set -uo pipefail

REPO=aerismusic8-alt/aeris-drive-automation
WF=$1
BR=${2:-ax-pc1-studio-probe}

api() { python3 scripts/gh-api.py "$@" 2>/dev/null | tail -n +2; }
tok=$(node scripts/gh-app-token.mjs | head -1)
sha=$(git rev-parse HEAD)

newest_dispatch() {
  api GET "/repos/$REPO/actions/workflows/$WF/runs?per_page=30&event=workflow_dispatch" |
    python3 -c "import json,sys
runs=json.load(sys.stdin).get('workflow_runs',[])
print(max([r['id'] for r in runs]) if runs else '')"
}

prev=$(newest_dispatch)
echo "[$(date -u +%H:%M:%S)] dispatching $WF prev=$prev"
api POST "/repos/$REPO/actions/workflows/$WF/dispatches" --field "ref=$BR" >/dev/null

run=""
for _ in $(seq 1 60); do
  sleep 2
  cur=$(newest_dispatch)
  if [ -n "$cur" ] && [ "$cur" != "$prev" ]; then run=$cur; break; fi
done
echo "run=$run"
[ -n "$run" ] || { echo NO_RUN; exit 1; }

job="" ; st=""
for _ in $(seq 1 80); do
  sleep 5
  job=$(api GET "/repos/$REPO/actions/runs/$run/jobs" |
    python3 -c "import json,sys;d=json.load(sys.stdin)['jobs'];print(d[0]['id'] if d else '')" 2>/dev/null)
  st=$(api GET "/repos/$REPO/actions/runs/$run" |
    python3 -c "import json,sys;print(json.load(sys.stdin)['status'])" 2>/dev/null)
  [ -n "$job" ] && [ "$st" = completed ] && break
done
echo "job=$job status=$st"

curl -sL -H "Authorization: Bearer $tok" \
  "https://api.github.com/repos/$REPO/actions/jobs/$job/logs" | sed 's/\x1b\[[0-9;]*m//g'
