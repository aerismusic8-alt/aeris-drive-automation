#!/usr/bin/env bash
# Give the experience its name and make it public, so it can be opened from a
# phone.
#
# Publishing a place does not set either of these. The place the first publish
# created had no name and was private, so
# https://www.roblox.com/games/<placeId> redirected to /Title-Unavailable and
# there was no way to reach the game from a phone.
#
# The name was the first half of that. The second half is visibility. A private
# universe is not reachable from its game page whatever it is called, and this
# one reported `visibility: PRIVATE`. The page kept reading Title-Unavailable
# after the name was set, which is what pointed here.
#
# `visibility` cannot be written through the universe PATCH. Sending it returns
# 200 and changes nothing, which is the worst kind of response: it looks like it
# worked. The legacy activate and deactivate endpoints are what actually flip it,
# and they take `legacy-universe:manage` rather than `universe:write`.
#
# Set EXPERIENCE_VISIBILITY=PRIVATE to take the game down again. Making the game
# public is a launch, and it is reversible.
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
# Both fields are read back after writing. A 200 is the API's word; the
# read-back is the evidence, and it reports the values that were there before,
# which is what shows the write landed.
#
# Exit codes:
#   0  fields set and confirmed, or deliberately skipped (no scope, no name)
#   1  a required local tool is missing
#   2  a write was accepted but a field did not change

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${CFG:-$ROOT/roblox-garden/src/shared/Config.luau}"
UNIVERSE_ID="${UNIVERSE_ID:-10771844216}"
ENDPOINT="https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID"
LEGACY_BASE="https://apis.roblox.com/legacy-develop/v1/universes/$UNIVERSE_ID"
VISIBILITY="${EXPERIENCE_VISIBILITY:-PUBLIC}"

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

# The description comes from Config too, so the game's identity lives in one
# place. A missing Tagline falls back to the name rather than to a stale string
# from the previous game.
TAGLINE=$(python3 - "$CFG" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'Config\.Tagline\s*=\s*"([^"]+)"', src)
print(m.group(1) if m else "")
PY
)
[ -n "$TAGLINE" ] || TAGLINE="$NAME"

if [ -z "$NAME" ]; then
  echo "NAME=SKIPPED reason=no_GameName_in_Config"
  exit 0
fi
echo "NAME_TARGET=$NAME"
echo "NAME_VISIBILITY_TARGET=$VISIBILITY"
echo "NAME_ENDPOINT=$ENDPOINT"

RESP_FILE="$(mktemp)"
READ_FILE="$(mktemp)"
trap 'rm -f "$RESP_FILE" "$READ_FILE"' EXIT

# field_of FILE KEY prints one field from a universe payload, or empty.
field_of() {
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("")
    raise SystemExit(0)
if isinstance(d, dict):
    print(d.get(sys.argv[2]) or "")
PY
}

# Reading needs universe:read, which the publishing key normally has. If it does
# not, the read is reported and the write is still attempted.
READ_CODE=$(curl -sS -o "$READ_FILE" -w '%{http_code}' -m 20 \
  -H "x-api-key: $ROBLOX_API_KEY" "$ENDPOINT" 2>/dev/null || echo 000)
echo "NAME_READ_HTTP=$READ_CODE"
BEFORE_NAME=$(field_of "$READ_FILE" displayName)
BEFORE_VIS=$(field_of "$READ_FILE" visibility)
echo "NAME_BEFORE=${BEFORE_NAME:-<empty>}"
echo "VISIBILITY_BEFORE=${BEFORE_VIS:-<empty>}"

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
    # Read back rather than trusting the write. This is the difference between
    # "the call succeeded" and "the game is named and reachable".
    READ2=$(curl -sS -o "$READ_FILE" -w '%{http_code}' -m 20 \
      -H "x-api-key: $ROBLOX_API_KEY" "$ENDPOINT" 2>/dev/null || echo 000)
    echo "NAME_READBACK_HTTP=$READ2"
    AFTER_NAME=$(field_of "$READ_FILE" displayName)
    AFTER_VIS=$(field_of "$READ_FILE" visibility)
    echo "NAME_AFTER=${AFTER_NAME:-<empty>}"
    echo "VISIBILITY_AFTER=${AFTER_VIS:-<empty>}"
    if [ "$AFTER_NAME" != "$NAME" ]; then
      echo "NAME=UNCONFIRMED expected=$NAME got=${AFTER_NAME:-<empty>}"
      exit 2
    fi
    echo "NAME=SET"

    if [ "$AFTER_VIS" = "$VISIBILITY" ]; then
      echo "VISIBILITY=SET"
      exit 0
    fi

    # visibility is read-only on this resource, so it is flipped through the
    # legacy activate/deactivate pair. Nothing else does it.
    if [ "$VISIBILITY" = "PUBLIC" ]; then
      ACTION=activate
    else
      ACTION=deactivate
    fi
    echo "VISIBILITY_ACTION=$ACTION"
    echo "VISIBILITY_ACTION_URL=$LEGACY_BASE/$ACTION"

    ACT_HTTP=$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X POST \
      -H "x-api-key: $ROBLOX_API_KEY" \
      "$LEGACY_BASE/$ACTION" 2>/dev/null || echo 000)
    echo "VISIBILITY_ACTION_HTTP=$ACT_HTTP"
    head -c 400 "$RESP_FILE" 2>/dev/null || true
    echo

    case "$ACT_HTTP" in
      200)
        READ3=$(curl -sS -o "$READ_FILE" -w '%{http_code}' -m 20 \
          -H "x-api-key: $ROBLOX_API_KEY" "$ENDPOINT" 2>/dev/null || echo 000)
        echo "VISIBILITY_READBACK_HTTP=$READ3"
        AFTER_VIS=$(field_of "$READ_FILE" visibility)
        echo "VISIBILITY_AFTER_ACTION=${AFTER_VIS:-<empty>}"
        if [ "$AFTER_VIS" = "$VISIBILITY" ]; then
          echo "VISIBILITY=SET"
        else
          echo "VISIBILITY=UNCONFIRMED expected=$VISIBILITY got=${AFTER_VIS:-<empty>}"
          exit 2
        fi
        ;;
      401|403)
        echo "VISIBILITY=SKIPPED reason=key_lacks_legacy-universe:manage_scope"
        echo "VISIBILITY_FIX=Creator Dashboard > Open Cloud > API Keys > this key"
        echo "VISIBILITY_FIX_ADD_API_SYSTEM=universes (add the manage operation)"
        ;;
      000) echo "VISIBILITY=SKIPPED reason=network_error" ;;
      *) echo "VISIBILITY=SKIPPED reason=http_$ACT_HTTP" ;;
    esac
    ;;
  401|403) echo "NAME=SKIPPED reason=key_lacks_universe:write_scope" ;;
  404) echo "NAME=SKIPPED reason=endpoint_or_key_not_accepted" ;;
  000) echo "NAME=SKIPPED reason=network_error" ;;
  *) echo "NAME=SKIPPED reason=http_$HTTP_CODE" ;;
esac

exit 0
