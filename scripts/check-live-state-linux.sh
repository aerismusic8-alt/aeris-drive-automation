#!/usr/bin/env bash
# Check the live state of the game from the outside, the way a player sees it.
#
# Why this exists. A green pipeline proved the wrong thing twice in one session:
# a place published with no name and a private universe, and both times every
# job passed while https://www.roblox.com/games/<placeId> said
# Title-Unavailable. The publish was real; the game was not reachable. Nothing
# in the pipeline looked at the thing a player would look at.
#
# So this asks the questions a player asks, from outside, and it needs no
# credential at all:
#
#   1. Does the game page resolve to the game, or to Title-Unavailable?
#   2. Does the games API agree with the name in Config.luau?
#   3. Is the universe public? (needs a key; skipped without one)
#
# A control game is checked first. If a game that is known to be public also
# fails to resolve, the network is the problem and this reports that instead of
# blaming the game. Without the control, an outage reads as a broken game.
#
# The page check looks at the redirect target, not the status. Both a working
# game and a Title-Unavailable one answer 301; only the destination differs, so
# a status-code check would pass either way.
#
# Exit codes:
#   0  every check passed
#   2  a check failed
#   3  could not determine (network)

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG_JSON="$ROOT/roblox/publish-config.json"
CFG_LUAU="${CFG_LUAU:-$ROOT/roblox/src/shared/Config.luau}"
CONTROL_PLACE="${CONTROL_PLACE:-920587237}"

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 3; }

if [ ! -f "$CFG_JSON" ]; then
  echo "CHECK=FAIL reason=missing_publish_config path=$CFG_JSON"
  exit 2
fi

read -r CFG_UNIVERSE_ID CFG_PLACE_ID <<EOF
$(python3 - "$CFG_JSON" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
print(cfg["universeId"], cfg["placeId"])
PY
)
EOF

# Overridable so the failure path can be exercised on purpose. A check that
# cannot be shown to fail is not a check.
UNIVERSE_ID="${UNIVERSE_ID:-$CFG_UNIVERSE_ID}"
PLACE_ID="${PLACE_ID:-$CFG_PLACE_ID}"

WANT_NAME=$(python3 - "$CFG_LUAU" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'Config\.GameName\s*=\s*"([^"]+)"', src)
print(m.group(1) if m else "")
PY
)

echo "CHECK universeId=$UNIVERSE_ID placeId=$PLACE_ID"
echo "CHECK expected_name=$WANT_NAME"

FAILED=0
note_fail() { echo "CHECK=FAIL reason=$1"; FAILED=1; }

# --- Control: prove the check itself works -------------------------------
CONTROL_URL=$(curl -sS -m 15 -o /dev/null -w '%{redirect_url}' \
  "https://www.roblox.com/games/$CONTROL_PLACE" 2>/dev/null || echo "")
case "$CONTROL_URL" in
  *Title-Unavailable*|"")
    echo "CHECK=INDETERMINATE reason=control_game_did_not_resolve url=$CONTROL_URL"
    echo "CHECK_NOTE=the network or Roblox is the problem, not this game"
    exit 3
    ;;
  *) echo "CONTROL=OK resolved=$(basename "$CONTROL_URL")" ;;
esac

# --- 1. Does the game page resolve to the game? --------------------------
GAME_URL=$(curl -sS -m 15 -o /dev/null -w '%{redirect_url}' \
  "https://www.roblox.com/games/$PLACE_ID" 2>/dev/null || echo "")
echo "GAME_PAGE_REDIRECT=$GAME_URL"

case "$GAME_URL" in
  *Title-Unavailable*)
    # The place exists but is not reachable. Private is the usual cause, and a
    # missing name shows up here too.
    note_fail game_page_says_Title_Unavailable
    ;;
  "")
    note_fail game_page_did_not_respond
    ;;
  "https://www.roblox.com/games/$PLACE_ID/"*)
    # A real game resolves to /games/<placeId>/<slug>. Anything else that is not
    # one of the cases above is a redirect to somewhere unexpected, such as
    # /request-error, which must not read as a pass.
    SLUG="${GAME_URL##*/}"
    if [ -z "$SLUG" ]; then
      note_fail game_page_slug_empty
    else
      echo "GAME_PAGE=OK slug=$SLUG"
    fi
    ;;
  *)
    note_fail "game_page_unexpected_redirect:$GAME_URL"
    ;;
esac

# --- 2. Does the public API agree with Config? ---------------------------
API_JSON=$(curl -sS -m 15 "https://games.roblox.com/v1/games?universeIds=$UNIVERSE_ID" 2>/dev/null || echo "")
NAME=$(printf '%s' "$API_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)['data'][0]
except Exception:
    print('')
    raise SystemExit(0)
print(d.get('name') or '')
")
echo "GAMES_API_NAME=$NAME"

if [ -z "$NAME" ]; then
  note_fail games_api_unreadable
elif [ "$NAME" = "[TITLE UNAVAILABLE]" ]; then
  note_fail games_api_reports_title_unavailable
elif [ -n "$WANT_NAME" ] && [ "$NAME" != "$WANT_NAME" ]; then
  echo "CHECK=FAIL reason=name_mismatch expected=$WANT_NAME got=$NAME"
  FAILED=1
else
  echo "GAMES_API=OK name_matches_config"
fi

# --- 3. Is the universe public? ------------------------------------------
if [ -z "${ROBLOX_API_KEY:-}" ]; then
  echo "VISIBILITY=SKIPPED reason=ROBLOX_API_KEY_not_set"
else
  VIS=$(curl -sS -m 20 -H "x-api-key: $ROBLOX_API_KEY" \
    "https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID" 2>/dev/null \
    | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('visibility') or '')
except Exception:
    print('')
")
  echo "VISIBILITY=$VIS"
  if [ "$VIS" = "PUBLIC" ]; then
    echo "VISIBILITY_CHECK=OK"
  elif [ -z "$VIS" ]; then
    echo "VISIBILITY_CHECK=UNKNOWN reason=unreadable"
  else
    note_fail visibility_is_not_public
  fi
fi

if [ "$FAILED" = "1" ]; then
  echo "LIVE_STATE=FAIL"
  exit 2
fi

echo "LIVE_STATE=PASS"
exit 0
