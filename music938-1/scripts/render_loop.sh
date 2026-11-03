#!/usr/bin/env bash
# Render every remaining song for free.
#
# Flow Music's free tier runs out of credits after a handful of songs, and the
# only free top-up is the Turntable (vote on two samples). So this alternates:
# render a few songs, then earn credits by voting, and repeat until nothing is
# left. Rule #1 forbids paying, so the loop must never touch an upgrade button.
#
#   scripts/render_loop.sh            # default: 4 songs per round, 12 votes
#   scripts/render_loop.sh 3 10
set -u
cd "$(dirname "$0")/.."
export PYTHONPATH="${PYTHONPATH:-/workspace/ax-tools/pylibs}"

PER_ROUND="${1:-4}"
VOTES="${2:-12}"

for round in $(seq 1 12); do
  echo "===== round ${round} $(date +%H:%M) ====="
  python3 scripts/render_remaining.py --limit "${PER_ROUND}"
  rc=$?
  left="$(python3 scripts/render_remaining.py --list | head -1)"
  echo "left: ${left}"
  case "${left}" in
    0\ song*) echo "ALL DONE"; exit 0 ;;
  esac
  if [ "${rc}" -eq 3 ]; then
    echo "LOGGED OUT — the operator must sign in again"; exit 3
  fi
  # rc 0 = rendered some (maybe about to run dry), rc 2 = already dry.
  echo "--- earning credits on the Turntable ---"
  python3 scripts/turntable_vote.py --rounds "${VOTES}"
done
echo "round limit reached"
