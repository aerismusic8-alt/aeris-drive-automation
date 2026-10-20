#!/usr/bin/env bash
# Run the AX Arena Luau test suite.
#
# Uses `luau` from PATH when available, otherwise falls back to the vendored
# copy under tools/ that scripts/install-luau.sh downloads.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v luau >/dev/null 2>&1; then
	LUAU="$(command -v luau)"
elif [ -x "$ROOT/tools/luau/luau" ]; then
	LUAU="$ROOT/tools/luau/luau"
else
	echo "luau not found. Install it with scripts/install-luau.sh" >&2
	exit 127
fi

# Unit tests cover the pure modules in isolation.
"$LUAU" "$ROOT/roblox/tests/run.luau" || exit 1

# Integration tests replay a real game loop, so a broken reward path fails
# here even when every unit test passes.
"$LUAU" "$ROOT/roblox/tests/integration.luau" || exit 1

# The story spine: every objective reachable, every reward paid once, every
# objective translated, and a corrupt save cannot lock a player out.
"$LUAU" "$ROOT/roblox/tests/quests.luau" || exit 1

# The HUD is written in fixed pixels against a 1280x720 reference and most of
# this game's players are on phones. This suite does the arithmetic a phone
# screen would do and fails when a panel no longer fits one.
"$LUAU" "$ROOT/roblox/tests/layout.luau" || exit 1

# Balance tests compare the player's power curve against the monster curve. The
# whole suite passed while bosses were mathematically unkillable, because no test
# asked whether the two curves met. This one does.
"$LUAU" "$ROOT/roblox/tests/balance.luau" || exit 1

# The runtime suite boots the real server, builds the real world and loads the
# real client under a headless engine shim. It needs the sources as a Luau table
# because the standalone CLI has no file I/O, so they are generated first.
python3 "$ROOT/scripts/gen-roblox-sources.py" || exit 1
"$LUAU" "$ROOT/roblox/tests/runtime.luau" || exit 1

# Wiring checks read the source, because the HUD cannot be executed outside
# Roblox. This is what catches a renamed label or an unbound button.
python3 "$ROOT/scripts/check-hud-wiring.py" || exit 1

# The lighting settings decide whether the game renders at all on a weak GPU,
# which is the hardware the target mobile players are closest to.
exec python3 "$ROOT/scripts/check-low-end-lighting.py"
