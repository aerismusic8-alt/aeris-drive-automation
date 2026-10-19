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
# Endpoint and scope come from the Universes feature reference:
#   PATCH /cloud/v2/universes/{universe_id}   scope: universe:write
#
# An earlier version of this script used /universes/v1/universes/{id}. That path
# does not exist, so every run reported a 404 that read like a missing scope and
# sent someone to add a scope they may already have had. The path below is the
# documented one.
#
# The name is read from Config.luau so it lives in one place with the rest of
# the game's identity.
#
# The script reads the name back after writing it. A 200 is the API's word; the
# read-back is the evidence, and it also shows what the name was before.
#
# Exit codes:
#   0  name set and confirmed, or deliberately skipped (no scope, no name)
#   1  a required local tool is missing
#   2  the write was accepted but the name did not change

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="$ROOT/roblox/src/shared/Config.luau"
UNIVERSE_ID="${UNIVERSE_ID:-10771844216}"
ENDPOINT="https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID"
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
echo "NAME_ENDPOINT=$ENDPOINT"
echo "NAME_TARGET=$NAME"

RESP_FILE="$(mktemp)"
READ_FILE="$(mktemp)"
trap 'rm -f "$RESP_FILE" "$READ_FILE"' EXIT

# read_display_name prints the current displayName, or an empty string.
read_display_name() {
  python3 - "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("")
    raise SystemExit(0)
if isinstance(d, dict):
    print(d.get("displayName") or "")
PY
}

# Reading needs universe:read, which the publishing key normally has. If it does
# not, the read is reported and the write is still attempted.
READ_CODE=$(curl -sS -o "$READ_FILE" -w '%{http_code}' -m 20 \
  -H "x-api-key: $ROBLOX_API_KEY" "$ENDPOINT" 2>/dev/null || echo 000)
echo "NAME_READ_HTTP=$READ_CODE"
BEFORE=$(read_display_name "$READ_FILE")
if [ -n "$BEFORE" ]; then
  echo "NAME_BEFORE=$BEFORE"
fi

BODY=$(python3 -c 'import json,sys;print(json.dumps({"displayName":sys.argv[1],"description":sys.argv[2]}))' "$NAME" "$TAGLINE")

# updateMask keeps the write to the two fields named, so nothing else on the
# universe is touched by accident.
HTTP_CODE=$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X PATCH \
  -H "x-api-key: $ROBLOX_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$BODY" \
  "$ENDPOINT?updateMask=displayName,description" 2>/dev/null || echo 000)

echo "NAME_HTTP=$HTTP_CODE"
head -c 400 "$RESP_FILE" 2>/dev/null || true
echo

case "$HTTP_CODE" in
  200)
    # Read it back rather than trusting the write. This is what makes the
    # difference between "the call succeeded" and "the name is now correct".
    READ2=$(curl -sS -o "$READ_FILE" -w '%{http_code}' -m 20 \
      -H "x-api-key: $ROBLOX_API_KEY" "$ENDPOINT" 2>/dev/null || echo 000)
    echo "NAME_READBACK_HTTP=$READ2"
    AFTER=$(read_display_name "$READ_FILE")
    echo "NAME_AFTER=$AFTER"
    if [ "$AFTER" = "$NAME" ]; then
      echo "NAME=SET"
    else
      echo "NAME=UNCONFIRMED expected=$NAME got=${AFTER:-<empty>}"
      exit 2
    fi
    ;;
  401|403) echo "NAME=SKIPPED reason=key_lacks_universe:write_scope" ;;
  404) echo "NAME=SKIPPED reason=endpoint_or_key_not_accepted" ;;
  000) echo "NAME=SKIPPED reason=network_error" ;;
  *) echo "NAME=SKIPPED reason=http_$HTTP_CODE" ;;
esac

exit 0
