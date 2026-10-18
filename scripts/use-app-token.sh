#!/usr/bin/env bash
# Point the repo's git remote at a freshly minted GitHub App installation
# token, then optionally push. Installation tokens expire after an hour, so
# run this before any push rather than editing the remote by hand.
#
#   ./scripts/use-app-token.sh                 # set remote only
#   ./scripts/use-app-token.sh push            # set remote and push
#   ./scripts/use-app-token.sh push origin HEAD:main
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_SLUG="aerismusic8-alt/aeris-drive-automation"

cd "$REPO_DIR"

TOKEN="$(node scripts/gh-app-token.mjs | head -1)"
if [ -z "$TOKEN" ]; then
	echo "Failed to mint an installation token." >&2
	exit 1
fi

git remote set-url origin "https://x-access-token:${TOKEN}@github.com/${REPO_SLUG}.git"
echo "Remote updated with a fresh installation token (valid ~1 hour)."

if [ "${1:-}" = "push" ]; then
	shift
	git push "$@"
fi
