#!/usr/bin/env bash
# Download the Luau CLI into tools/luau so tests can run without a system install.
# Idempotent: re-running reuses an existing binary unless FORCE=1 is set.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/tools/luau"
VERSION="${LUAU_VERSION:-0.743}"

if [ -x "$DEST/luau" ] && [ "${FORCE:-0}" != "1" ]; then
	echo "luau already present at $DEST/luau"
	exit 0
fi

case "$(uname -s)" in
	Linux) ASSET="luau-ubuntu.zip" ;;
	Darwin) ASSET="luau-macos.zip" ;;
	*)
		echo "unsupported platform: $(uname -s)" >&2
		exit 1
		;;
esac

URL="https://github.com/luau-lang/luau/releases/download/${VERSION}/${ASSET}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $URL"
if command -v curl >/dev/null 2>&1; then
	curl -fsSL -o "$TMP/luau.zip" "$URL"
elif command -v wget >/dev/null 2>&1; then
	wget -q -O "$TMP/luau.zip" "$URL"
else
	echo "need curl or wget" >&2
	exit 1
fi

mkdir -p "$DEST"
if command -v unzip >/dev/null 2>&1; then
	unzip -o "$TMP/luau.zip" -d "$DEST" >/dev/null
else
	python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TMP/luau.zip" "$DEST"
fi

chmod +x "$DEST"/luau "$DEST"/luau-analyze "$DEST"/luau-compile "$DEST"/luau-ast 2>/dev/null || true
echo "Installed Luau $VERSION to $DEST"
