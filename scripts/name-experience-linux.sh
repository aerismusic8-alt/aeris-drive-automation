#!/usr/bin/env bash
# Give the experience its name, so its page stops reading "Title-Unavailable"
# and the game can be opened from a phone.
#
# Publishing a place does not set the experience name. The place the first
# publish created had none, so https://www.roblox.com/games/<placeId> redirected
# to /Title-Unavailable and there was no way to reach the game from a phone.
# The Universes API sets it, and this script calls that endpoint.
#
# The name is read from Config.luau so it lives in one place with the rest of
# the game's identity.
#
# Setting a name needs universe:write. A key minted only for place publishing
# has universe-places:write, and this endpoint answers 404 for a key it will not
# accept, which is the same response as an unknown path. It does not tell the
# two apart, so the outcome is reported as-is and never treated as fatal: a key
# that cannot rename the experience must not block shipping the game.
#
# Exit codes:
#   0  name set, or deliberately skipped (no scope, or no name in Config)
#   1  a required local tool is missing
#   2  a real API error (5xx, or a body that is not what we sent)

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="$ROOT/roblox/src/shared/Config.luau"
UNIVERSE_ID="${UNIVERSE_ID:-10771844216}"
TAGLINE="A Ragnarok-style legendary MMORPG. Central town Prontera, five monster fields, classes, skills, pets and rebirth."

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found" >&2; exit 1; }

if [ -z "${ROBLOX_API_KEY:-}" ]; then
  echo "NAME=SKIPPED reason=ROBLOX_API_KEY_not_set"
  exit 0
fi

NAME=$(python3 - "$CFG" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'Config\.GameName\s*=\s*"([^"]+)"', src)
print(m.group(1) if m else "")
PY
)

if [ -z "$NAME" ]; then
  echo "NAME=SKIPPED reason=no_GameName_in_Config"
  exit 0
fi
echo "NAME_TARGET=$NAME"

RESP_FILE="$(mktemp)"
trap 'rm -f "$RESP_FILE"' EXIT

BODY=$(python3 -c 'import json,sys;print(json.dumps({"displayName":sys.argv[1],"description":sys.argv[2]}))' "$NAME" "$TAGLINE")

HTTP_CODE=$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X PATCH \
  -H "x-api-key: $ROBLOX_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$BODY" \
  "https://apis.roblox.com/universes/v1/universes/$UNIVERSE_ID" || echo 000)

echo "NAME_HTTP=$HTTP_CODE"
head -c 400 "$RESP_FILE" 2>/dev/null || true
echo

case "$HTTP_CODE" in
  200)
    # A 200 that echoed a different name back would mean the request was not
    # applied as asked, so the response is checked rather than trusted.
    APPLIED=$(python3 - "$RESP_FILE" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("")
    raise SystemExit(0)
for k in ("displayName", "name"):
    if isinstance(d, dict) and d.get(k):
        print(d[k]); break
PY
)
    if [ -n "$APPLIED" ] && [ "$APPLIED" != "$NAME" ]; then
      echo "NAME=MISMATCH applied=$APPLIED"
      exit 2
    fi
    echo "NAME=SET"
    ;;
  401|403) echo "NAME=SKIPPED reason=key_lacks_universe_write_scope" ;;
  404) echo "NAME=SKIPPED reason=key_lacks_universe_write_scope_or_unknown_endpoint" ;;
  000) echo "NAME=SKIPPED reason=network_error" ;;
  *) echo "NAME=SKIPPED reason=http_$HTTP_CODE" ;;
esac

exit 0
