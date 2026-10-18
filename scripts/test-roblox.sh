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
exec "$LUAU" "$ROOT/roblox/tests/integration.luau"
