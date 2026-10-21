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

PLACE="${1:-AXGarden.rbxlx}"
VERSION_TYPE="${2:-Published}"
CONFIG="${CONFIG:-roblox-garden/publish-config.json}"

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
  # 403 is the one failure with a known, fixed cause, but the message decides
  # which cause. A key has two independent locks:
  #
  #   "Scope not authorized"     -> the key lacks universe-places:write.
  #   "Resources not authorized" -> the scope is present but the key's target
  #                                 restrictions do not include this experience.
  #
  # They are worth telling apart because the fixes are in different screens and
  # doing one when the other is missing changes nothing. No probe catches either
  # in advance: this POST is the only endpoint that uses the scope, so publishing
  # is the test.
  if [ "$HTTP_CODE" = "403" ]; then
    if printf '%s' "$BODY" | grep -qi "Resources not authorized"; then
      echo "PUBLISH_DIAGNOSIS=key_experience_restrictions_exclude_this_place"
      echo "PUBLISH_FIX_1=Creator Dashboard > Open Cloud > API Keys > edit the key used by ROBLOX_API_KEY"
      echo "PUBLISH_FIX_2=Experience Restrictions: add this experience, or drop the restriction"
      echo "PUBLISH_FIX_3=An alternate key scoped to this experience works too; point the workflow at it"
    else
      echo "PUBLISH_DIAGNOSIS=key_lacks_universe-places:write"
      echo "PUBLISH_FIX_1=Creator Dashboard > Open Cloud > API Keys > edit the key used by ROBLOX_API_KEY"
      echo "PUBLISH_FIX_2=Access Permissions: add API system 'universe-places'"
      echo "PUBLISH_FIX_3=For that system, tick the 'Write' operation for this experience"
      echo "PUBLISH_FIX_4=Keep 'Restrict by Experience' on, with this experience selected"
    fi
  fi
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
