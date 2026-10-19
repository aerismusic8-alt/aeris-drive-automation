#!/usr/bin/env bash
# Publish a built place to Roblox through the Open Cloud API, without PC1.
#
# The previous publish path required PC1 only because it was written there, not
# because publishing needs it. The operation is one HTTPS POST of the place file
# to the versions endpoint, which any machine with the key can do.
#
# Needs ROBLOX_API_KEY in the environment, scoped universe-places:write.
# Reads universeId and placeId from roblox/publish-config.json.
#
# Usage:
#   ROBLOX_API_KEY=... bash scripts/publish-place-linux.sh AXArena.rbxlx [Saved|Published]
#
# Reports BLOCKED and exits 3 when the credential is absent. It never reports a
# publish that did not happen.

set -uo pipefail

PLACE="${1:-AXArena.rbxlx}"
VERSION_TYPE="${2:-Published}"
CONFIG="${CONFIG:-roblox/publish-config.json}"

if [ ! -s "$PLACE" ]; then
  echo "PLACE_FILE_MISSING=$PLACE" >&2
  exit 2
fi
if [ ! -f "$CONFIG" ]; then
  echo "PUBLISH_CONFIG_MISSING=$CONFIG" >&2
  exit 2
fi

read -r UNIVERSE_ID PLACE_ID <<EOF
$(python3 - "$CONFIG" <<'PY'
import json
import sys

cfg = json.load(open(sys.argv[1]))
print(cfg["universeId"], cfg["placeId"])
PY
)
EOF

if [ -z "${ROBLOX_API_KEY:-}" ]; then
  echo "PUBLISH=BLOCKED reason=ROBLOX_API_KEY_not_set"
  echo "UNIVERSE_ID=$UNIVERSE_ID PLACE_ID=$PLACE_ID"
  exit 3
fi

URL="https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=${VERSION_TYPE}"
echo "PUBLISH_URL=$URL"
echo "PLACE_BYTES=$(wc -c < "$PLACE")"

RESP_FILE="$(mktemp)"
HTTP_CODE=$(curl -sS -o "$RESP_FILE" -w '%{http_code}' \
  -X POST "$URL" \
  -H "x-api-key: ${ROBLOX_API_KEY}" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary "@${PLACE}" || echo "000")

echo "PUBLISH_HTTP=$HTTP_CODE"
BODY=$(cat "$RESP_FILE")
rm -f "$RESP_FILE"
echo "PUBLISH_RESPONSE=$BODY"

if [ "$HTTP_CODE" != "200" ]; then
  echo "PUBLISH=FAILED"
  exit 4
fi

# Roblox returns the new versionNumber. That number is the authoritative record
# that a version now exists, so it is required, not optional.
VERSION_NUMBER=$(python3 -c "
import json,sys
try:
    print(json.loads(sys.argv[1]).get('versionNumber',''))
except Exception:
    print('')
" "$BODY")

if [ -z "$VERSION_NUMBER" ]; then
  echo "PUBLISH=UNVERIFIED reason=no_versionNumber_in_response"
  exit 5
fi

echo "PUBLISH_VERSION_NUMBER=$VERSION_NUMBER"
echo "PUBLISH=OK universeId=$UNIVERSE_ID placeId=$PLACE_ID versionType=$VERSION_TYPE"
