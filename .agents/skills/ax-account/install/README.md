# Make this skill global for the whole account (one-time, operator)

OpenHands loads **organization-level skills** from a GitHub repository named
exactly **`.agents`** under the account. Every repository of that account then sees
the skills in `skills/`. This is the only route that reaches *all* repositories and
*all* conversations with no per-session install.

Verified against this agent-server (2026-10-29):

- The repo **root** must contain `skills/` — not `.agents/skills/`. The loader
  clones the repo and reads `<clone>/skills/<name>/SKILL.md`.
- The repo may be **public**; no token is needed to read it.
- The name must be **`.agents`** (plural). A repo named `.agent` (singular) is not
  auto-discovered. The platform *can* point at any name through an explicit
  `org_configs` entry, but that is supplied at conversation start, not by the skill
  author — so use the exact name.
- The sandbox token cannot create a repo, rename one, or push (all 403), so this is
  an operator action.

## Steps

1. **Name the repository `.agents`** under `aerismusic8-alt`.
   - If you already created `.agent`, rename it: repo → **Settings** → *Rename*.
   - Otherwise: https://github.com/new → name `.agents` → Create.

2. **Put this layout at the repository root** (no `.agents/` wrapper):

   ```
   .agents/                 <- the repository root
   └── skills/
       └── ax-account/
           ├── SKILL.md
           ├── references/
           └── scripts/
   ```

3. **Upload** it. The ready tree is built by the bundled script:

   ```bash
   cd "$(git rev-parse --show-toplevel)/.agents/skills/ax-account"
   bash scripts/make-org-agents-repo.sh            # builds /tmp/org-agents-repo
   bash scripts/make-org-agents-repo.sh --push     # builds and pushes (needs write)
   ```

   If the sandbox token still cannot write, upload the printed tree through the
   GitHub web UI ("Add file → Upload files" accepts a dragged folder), or push from
   PC1 (`scripts/push-via-pc1.sh`). A zip of the tree is also kept at
   `/workspace/ax-tools/org-agents-upload.zip`.

## Keeping it current

`<repo>/.agents/skills/ax-account/` is the source of truth. Re-run
`scripts/make-org-agents-repo.sh` after a change so the two copies cannot drift.

## Fallback if the operator cannot create `.agents`

The repository copy plus `scripts/install-agent-skills.sh` (user-level, per pod) is
a working substitute. It is not truly global, but it restores the skill in every
conversation after a recycle with one command.
