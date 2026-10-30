#!/usr/bin/env bash
# Install the account skill so it loads in EVERY conversation, not only ones opened
# in this repository.
#
# Why this is needed: skills load from the project (.agents/skills/) and from the
# user directory (~/.agents/skills/). The project copy is tracked in git and
# survives a pod recycle; ~/.agents/skills/ is on the ephemeral overlay and does
# not. Running this after a recycle restores the user-level copy, which is the one
# that reaches every conversation.
#
#   bash scripts/install-agent-skills.sh          # install from this repo
#   bash scripts/install-agent-skills.sh --check   # report what is installed
#
# The org-wide route (a GitHub repo named ".agents") is a one-time operator action
# and is prepared under install/org-agents-repo/.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"          # .../.agents/skills/ax-account
USER_SKILLS="$HOME/.agents/skills"

if [ "${1:-}" = "--check" ]; then
  echo "project: $SKILL_DIR/SKILL.md"
  [ -f "$SKILL_DIR/SKILL.md" ] && echo "  present" || echo "  MISSING"
  echo "user:    $USER_SKILLS/ax-account/SKILL.md"
  [ -f "$USER_SKILLS/ax-account/SKILL.md" ] && echo "  present" || echo "  MISSING"
  exit 0
fi

mkdir -p "$USER_SKILLS"
rm -rf "$USER_SKILLS/ax-account"
cp -r "$SKILL_DIR" "$USER_SKILLS/ax-account"
echo "[+] installed ax-account -> $USER_SKILLS/ax-account"
echo "    it now loads in every conversation for this user"
echo
echo "Verify with the agent server (no secret printed):"
echo '  SK=$(tr "\0" "\n" < /proc/1/environ | grep ^SESSION_API_KEY= | cut -d= -f2-)'
echo '  curl -s -H "X-Session-API-Key: $SK" http://127.0.0.1:60000/api/skills/catalog \'
echo '    | python3 -c "import json,sys;print([s[\"name\"] for s in json.load(sys.stdin)[\"skills\"] if s.get(\"origin\")==\"user\"])"'
