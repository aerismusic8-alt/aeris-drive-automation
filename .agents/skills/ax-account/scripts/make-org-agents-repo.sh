#!/usr/bin/env bash
# Build the org-level ".agents" repository tree from the real skill, then push it.
#
# Why: OpenHands loads organization/user skills from a GitHub repository named
# ".agents" under the account. That repo does not exist yet and the sandbox token
# cannot create one (403) — creating it is a one-time operator action. This script
# produces the exact tree to upload, so the two copies cannot drift.
#
#   bash scripts/make-org-agents-repo.sh            # build the tree under /tmp
#   bash scripts/make-org-agents-repo.sh --push      # build, commit, push (needs write)
#
# After the repo exists, re-run this whenever the skill changes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"          # .../.agents/skills/ax-account
OUT="${OUT:-/tmp/org-agents-repo}"
REMOTE="https://x-access-token:${GITHUB_TOKEN:-}@github.com/aerismusic8-alt/.agents.git"

rm -rf "$OUT"
mkdir -p "$OUT/skills"
cp -r "$SKILL_DIR" "$OUT/skills/ax-account"
rm -rf "$OUT/skills/ax-account/install"      # the installer must not recurse

echo "[+] built $OUT"
find "$OUT" -type f | sed "s#$OUT/##"

if [ "${1:-}" = "--push" ]; then
  cd "$OUT"
  git init -q
  git add -A
  git -c user.name=openhands -c user.email=openhands@all-hands.dev \
      commit -qm "skill: ax-account account playbook"
  git branch -M main
  git remote add origin "$REMOTE"
  git push -u origin main
fi
