#!/usr/bin/env bash
# Report which Open Cloud capabilities the key actually has.
#
# An API key is a list of ticked scopes, and the only way to know what was
# ticked is to ask Roblox. This probes one read-only endpoint per capability and
# prints a verdict, so "what can the automation do" is measured rather than
# assumed.
#
# Every probe is a GET. Nothing here writes, publishes, or restarts anything, so
# it is safe to run against the live experience as often as you like.
#
# Reading the verdicts:
#   GRANTED  the call succeeded; the key has the scope
#   DENIED   the call was refused; the scope is missing (or the key is wrong)
#   401/403/404 are all reported as DENIED. Roblox answers 404 for a key it will
#   not accept, which is the same status as a path that does not exist, so the
#   two cannot be told apart from outside. Both mean the call did not work.
#
# Exit code is always 0. This is a report, not a gate.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIVERSE_ID="${UNIVERSE_ID:-10771844216}"
PLACE_ID="${PLACE_ID:-79945905295644}"

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }

if [ -z "${ROBLOX_API_KEY:-}" ]; then
  echo "PROBE=SKIPPED reason=ROBLOX_API_KEY_not_set"
  exit 0
fi

echo "PROBE universeId=$UNIVERSE_ID placeId=$PLACE_ID"
printf '%-26s %-6s %-9s %s\n' CAPABILITY HTTP VERDICT "SCOPE THE DOCS NAME"

# label | url | scope
PROBES="
universe_read|https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID|universe:read
place_read|https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID/places/$PLACE_ID|universe.place:read
data_stores|https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID/data-stores|universe-datastores.control:list
secrets|https://apis.roblox.com/cloud/v2/universes/$UNIVERSE_ID/secrets|universe.secret:read
place_history|https://apis.roblox.com/place-version-history-api/v1/$PLACE_ID/history|place-version-history:read
team_create|https://apis.roblox.com/legacy-develop/v1/places/$PLACE_ID/teamcreate/active_session/members|legacy-team-collaboration:manage
universe_stats|https://apis.roblox.com/v1/universes/$UNIVERSE_ID/stats|universe:read
universe_config|https://apis.roblox.com/v1/universes/$UNIVERSE_ID/configuration|universe:read
badges|https://apis.roblox.com/legacy-develop/v1/universes/$UNIVERSE_ID/badges|legacy-badge:manage
game_passes|https://apis.roblox.com/legacy-develop/v1/universes/$UNIVERSE_ID/game-passes|legacy-game-pass:manage
developer_products|https://apis.roblox.com/legacy-develop/v1/universes/$UNIVERSE_ID/developer-products|legacy-developer-product:manage
localization|https://apis.roblox.com/legacy-game-internationalization/v1/universes/$UNIVERSE_ID/name-description|legacy-universe:manage
"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "$PROBES" | while IFS='|' read -r label url scope; do
  [ -z "$label" ] && continue
  code=$(curl -sS -o "$TMP" -w '%{http_code}' -m 20 -H "x-api-key: $ROBLOX_API_KEY" "$url" 2>/dev/null || echo 000)
  case "$code" in
    200) verdict=GRANTED ;;
    401|403|404) verdict=DENIED ;;
    000) verdict=NO_NETWORK ;;
    *) verdict="HTTP_$code" ;;
  esac
  printf '%-26s %-6s %-9s %s\n' "$label" "$code" "$verdict" "$scope"
done

# Publishing is proved by the publish job, not by a probe: a GET cannot show a
# write scope, and the POST is the only honest test. Recorded here so the report
# is complete.
echo ""
echo "publish_place            -      SEE_JOB    universe-places:write"
echo "PROBE_DONE"
