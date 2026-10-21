#!/usr/bin/env bash
# Can the Open Cloud key read Breachline's source?
#
# Breachline: Two Sites (universe 10772257179, root place 136310542172942) was
# created in Studio and its source exists on no machine we can reach. The one
# remaining place it could live is Roblox itself. This asks whether the key can
# read it back, and saves any place file it manages to fetch.
#
# Every call is a GET. Nothing here writes, publishes or restarts anything, so
# it is safe to run against the live experience as often as you like.
#
# Exit code is always 0. This is a report, not a gate.

set -u

UNIVERSE_ID="${UNIVERSE_ID:-10772257179}"
PLACE_ID="${PLACE_ID:-136310542172942}"
OUT="${OUT:-probe-out}"

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
mkdir -p "$OUT"

if [ -z "${ROBLOX_API_KEY:-}" ]; then
  echo "PROBE=SKIPPED reason=ROBLOX_API_KEY_not_set"
  exit 0
fi

echo "PROBE universeId=$UNIVERSE_ID placeId=$PLACE_ID"
printf '%-24s %-6s %s\n' CAPABILITY HTTP VERDICT

probe() {
  label="$1"; url="$2"
  code=$(curl -sS -o "$OUT/$label.body" -w '%{http_code}' -m 30 \
    -H "x-api-key: $ROBLOX_API_KEY" "$url" 2>/dev/null || echo 000)
  case "$code" in
    200) verdict=GRANTED ;;
    401|403|404) verdict=DENIED ;;
    000) verdict=NO_NETWORK ;;
    *) verdict="HTTP_$code" ;;
  esac
  printf '%-24s %-6s %s\n' "$label" "$code" "$verdict"
  echo "  URL=$url"
  if [ "$verdict" = "GRANTED" ]; then
    head -c 300 "$OUT/$label.body" | tr -d '\r\n'; echo
  fi
}

probe universe_read      "https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID"
probe places_list        "https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID/places?maxPageSize=50"
probe place_read         "https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID/places/$PLACE_ID"
probe place_history      "https://apis.roblox.com/place-version-history-api/v1/$PLACE_ID/history"
probe asset_delivery_v1  "https://apis.roblox.com/asset-delivery-api/v1/assetId/$PLACE_ID"
probe asset_delivery_v2  "https://apis.roblox.com/asset-delivery-api/v2/universes/$UNIVERSE_ID/places/$PLACE_ID"
probe legacy_v1          "https://assetdelivery.roblox.com/v1/asset/?id=$PLACE_ID"
probe legacy_v2          "https://assetdelivery.roblox.com/v2/assetId/$PLACE_ID"

# A place file saved by asset delivery is the source we could not find anywhere
# else. Detect it by content, not by status: a 200 can still be a JSON error.
for f in "$OUT"/asset_delivery_*.body; do
  [ -f "$f" ] || continue
  if head -c 8 "$f" | grep -q '<roblox'; then
    cp "$f" "$OUT/breachline-place.rbxlx"
    echo "PLACE_FILE=SAVED name=breachline-place.rbxlx bytes=$(wc -c < "$f")"
  fi
done

echo "PROBE_DONE"
