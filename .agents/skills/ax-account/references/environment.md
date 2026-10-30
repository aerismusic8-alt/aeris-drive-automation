# Environment

What the sandbox actually is, and which routes work. Everything here was measured;
when reality disagrees, believe reality and update this file.

## The sandbox

- Linux, x86_64, `node` and `npm` available. **No Roblox Studio** — game logic must
  stay testable under the plain Luau CLI.
- **`unzip` is not installed.** Extract with
  `python3 -c "import zipfile; zipfile.ZipFile(p).extractall(d)"`.
- **The shell mangles `<<'EOF'` heredocs** (tab completion fires inside). Use the
  file editor or `printf '%s\n' 'line'`.
- **`$HOME` is ephemeral; only `/workspace` survives a pod recycle.** The overlay
  is discarded. Persistent state — the Chromium/Google profile, installed skills,
  the Drive session — lives under `/workspace` (`/workspace/ax-tools/...`).
- The session exposes `work-1-...` (VNC/desktop) and `work-2-...` (HTTP) hosts;
  these change per pod. The work host is per-pod, so a hardcoded default goes stale.
  `hostname` returns the k8s pod name and answers 404 — use the work_hosts block.

## Skill discovery (verified)

Skills load from these locations, highest precedence first:

| Scope | Path | Reaches |
|---|---|---|
| Project | `<workspace>/.agents/skills/<name>/SKILL.md` | that repo's conversations |
| User | `~/.agents/skills/<name>/SKILL.md` | **all** conversations for this user |
| Public | the OpenHands extensions registry (cached) | conversations configured to load it |

Confirmed empirically: a skill written to `~/.agents/skills/` appears in the agent
server's skill catalog with `origin: "user"`. The server API to inspect it:

```bash
SK=$(tr '\0' '\n' < /proc/1/environ | grep '^SESSION_API_KEY=' | cut -d= -f2-)
curl -s -H "X-Session-API-Key: $SK" http://127.0.0.1:60000/api/skills/catalog
```

`X-Session-API-Key` is the working header (`Authorization: Bearer` returns 401).
`POST /api/skills/install` installs into `~/.openhands/skills/installed/` — also
ephemeral.

**Because `~/.agents/skills/` is ephemeral, the durable home of this skill is the
repository's `.agents/skills/` (tracked in git). After a recycle, run
`scripts/install-agent-skills.sh` to copy it back into `~/.agents/skills/` so it
loads in *every* conversation, not only ones opened in this repo.**

**Truly global (every repo of the account).** OpenHands loads organization skills
from a GitHub repository named exactly **`.agents`** under the account. Verified
against this server: the loader clones the repo and reads **`<clone>/skills/<name>/SKILL.md`**
— `skills/` sits at the repo *root*, not under `.agents/`. The repo may be public
(no token needed to read it). The name must be `.agents` (plural); a repo named
`.agent` is not auto-discovered.

K created a repo named `.agent` (singular) on 2026-10-29 — it needs renaming to
`.agents` (repo → Settings → Rename), then the tree from
`scripts/make-org-agents-repo.sh` uploaded to its root. The sandbox token cannot
create, rename or push (all 403), so both steps are operator actions.

The server *can* be pointed at an arbitrary repo name via an `org_configs` entry in
`POST /api/skills` (`{"repository","provider","org_repo_url","org_name"}`), but that
config is supplied when a conversation starts, not persisted by a PATCH to
`/api/settings` (verified: the patch returns 200 and is then gone). Do not rely on
it; fix the repo name instead.

## Git and GitHub

- **The sandbox `GITHUB_TOKEN` cannot write.** It is a GitHub App installation
  token: `x-oauth-scopes` empty, `allows_permissionless_access=true`. Every push
  is **403**, `workflow_dispatch` is **403** ("Resource not accessible by
  integration"). `GET /repos/...` reporting `permissions.push=true` is K's role,
  not the token's scope — test a real write, do not trust the field.
- **Write access lives on PC1** (a classic PAT). `scripts/push-via-pc1.sh` bundles
  the repo, hands it to PC1 over the port-12001 HTTP server, and PC1 pushes. It
  must `git fetch --unshallow` first (a bundle of a shallow clone cannot be cloned).
  **Currently blocked:** PC1 `/health` is 200 but `/mcp` is 401 with both
  `PC1_MCP_TOKEN` and `PC1_MCP_TOKEN_2` — the remote auth key needs rotating.
- `scripts/gh-api.py` mints its own App token per run; the App key is gone
  (`~/.config/aeris/` was on the overlay; `ax_vault.py` excludes `.pem`).
- Clone private repos with
  `https://x-access-token:${GITHUB_TOKEN}@github.com/OWNER/REPO.git`.
- Rate limits are per account and were never the constraint (5,000/hr, ~12 used).
  Repository size is the one to watch: media goes to a Release, never into git.

## Delivery

- **Google Drive is blocked on all three routes:** (1) `GDRIVE_REFRESH_TOKEN` is
  valid and carries `drive.file`, but the Drive API is **disabled in the owning
  Cloud project** → 403; (2) PC1 Drive File Stream `/mcp` → 401; (3) the desktop
  Chromium Google session is expired ("Signed out").
- **The reliable route is the operator signing in once** via noVNC, after which
  `scripts/gdrive-upload-browser.py` uploads through the browser (no API). See the
  `ax-cloud-desktop` skill.
- A pod-local static server (`python3 -m http.server` on the `work-2-...` host) is
  a **preview only** — it dies on recycle. Do not treat it as delivery.

## Login-only web apps (cloud desktop)

- Flow Music (`flowmusic.app`) and Gemini web (`gemini.google.com`) have **no API**.
  Drive them through the persistent cloud desktop. Read the `ax-cloud-desktop`
  skill first.
- The operator signs in once; **the agent never types the Google password.**
- Chrome needs `--remote-allow-origins='*'` or every CDP websocket is refused with
  403, even though the browser runs.
- `vnc.html` returns 200 even when the VNC backend is dead — run
  `bootstrap.py --status`, not a curl, to know if the desktop is up.
- After a recycle, a stale `SingletonLock` in the profile (a symlink into the dead
  pod's `/tmp`) stops Chromium binding 9222. Fix: `pkill -9 -f /usr/lib/chromium;
  rm -f <profile>/Singleton* <profile>/DevToolsActivePort`, then relaunch.

## Toolchain

- **Luau:** `scripts/test-roblox.sh` (uses `luau` from PATH, else `tools/luau`).
  `luau-compile --binary <file>` syntax-checks the Roblox glue and needs a file
  path, not stdin. No `as` casts, no bitwise operators (see conventions).
- **Media:** `ffmpeg` / `ffprobe` for stream and LUFS checks.
- **Narration:** `edge-tts` (free, no key) — two Thai voices.
- **Images:** Openverse API (free, no key). **Fonts:** Kanit, Prompt (OFL).
- **Python:** stdlib is usually enough; `zipfile` replaces the missing `zip`.
  Playwright (sync) + `browser.connect_over_cdp` drives the desktop Chromium.
