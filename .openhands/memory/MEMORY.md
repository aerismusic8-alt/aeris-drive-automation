# MEMORY — index

**How to use.** Injected index, small on purpose — the prompt truncates a long one
and the *oldest* text is lost first. Rules, roles and pointers only. Full detail:
`.openhands/memory/MEMORY-ARCHIVE.md` (~200 KB) and the daily logs beside this file.
**Maintenance:** add short lines; past ~6 KB fold the oldest into the archive and
leave a pointer. A truncated index silently deletes the rules at the top.

## Roles and method (K, 2026-10-31)

- **K = ผู้มีอำนาจตัดสินใจสูงสุด (Final Authority).** Every standing rule is K's.
- **AR = me.** I administer **ทุกอย่างแทน K ได้ทั้งหมด** — all of K's work, in K's
  place: decide, execute, report; no per-step approval. When I must choose, I pick
  the option that satisfies K's rules and say what I chose and why. K: **"อนุมัติให้
  บริหารงาน ตัดสินใจแทน K ทุกอย่างเลย"** — AR hands a decision back to K only when
  the action needs a credential or authority only K holds.
- **Method: PCSEV — P**roblem, **C**ause, **S**olution, **E**xecute, **V**erify.
  State each step. Do not skip to Execute.

## AR identity — AR's own mailbox and profile (K, 2026-10-31)

K authorised AR to hold its own identity — a mailbox plus a persistent browser
profile — and to open accounts with it. Kept **outside** the repo (it is public)
at `/workspace/ax-tools/ar-identity/` (survives a recycle): `creds.json`
(mailbox `araeris2909e0@fldubai.com`, mail.tm), `browser-profile/` (where
sign-ins live), `secrets.json` (per-service passwords), `accounts.json` (the
register). Tools in `ops/`: `ar_identity.py ensure|whoami|inbox|read` (the
mailbox over the mail.tm API — AR reads its own verification mail),
`ar_browser.py open|shot|text` (persistent profile), `ar_accounts.py add|list|status`.

**Finding:** a free-mailbox signup is blocked almost everywhere by design (captcha
at archive.org, OSM, Wikimedia, Codeberg, Neocities, PythonAnywhere, deSEC, GitLab;
disposable domain / datacenter IP rejected at sourcehut, Hugging Face). The mailbox
and profile are reusable, but **a captcha signup needs K signed in to the cloud
desktop** — AR then drives that authenticated browser and never types a password.
(mail.tm rejects a local part containing `.` — create 201s, login 401s.)

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only

Everything must be 100% free. A paid API, subscription or credit pack is out, not
a trade-off. Free routes only: login-only web apps driven through headful
Chromium (Gemini web, Flow Music), open APIs, self-hosted tooling.
**The agent must never type a password** — drive the browser K has signed into.
K's related rules: **AUDIO FIRST** (retention is the sound, not the picture);
delete the duplicate and the worthless, never archive; K reviews a channel's first
work; never rename a channel without K's approval.

## What this project is (K's goal)

K: "เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands นี่คือเป้าหมายของ k" — the
deliverable is **the agent**, not a hand-built channel, built from free
generative-AI cloud tools. Scope = **4 channels** (spec 2026-10-23: ch1 series/
drama, ch2 dhamma, ch3 3D anime, ch4 record label). Two standing goals in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` must never be closed as ordinary tasks:
a Roblox game anyone can enter and play, and real revenue from it.

- Rail + channel registry: `ops/` (`yt_auth.py whoami|videos`, `yt_publish.py`,
  `yt_branding.py`, `ax_channels.json`, `AX_CHANNELS.md`). If it vanishes, restore
  from the vault (`$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py`, KV key
  `axvault:readme`) or the archive.
- **ch3 `@aerismusicth`** `UCm44BjAn03ruOF-WaA3ZRww` = the revenue goal: pass
  YouTube's threshold (**1,000 subs AND 4,000 watch-hours/12 mo**, or 1,000 subs
  AND 10M Shorts views/90 days). Measured 2026-10-30: 0 subs, 8 videos, 442 views.
  Free lever = long-form volume (`compile_album.py`; a 60-min compilation earns
  1 h/view vs 3 min for a song). Quota: 10,000 units/day, 1,600/upload → ~6/day.

## music938-1 — Thai karaoke pack (2026-10-30, detail in archive)

20 songs: lyrics, a **real sung vocal** (Flow Music, free/login-only), a
true-instrumental karaoke mix, cover art, a 1920x1080 word-synced video.

- **429 is account-wide and time-windowed, not parallelism:** `--workers 1`;
  windows UTC 23,0,1,2,6,18; dead zone 07-17. Queue a song with no take first.
- **An Extend renders as `audio__render_edit`, not `audio__extend_song`** — the
  blocker on all 20 songs: `_wait_new_clip` accepted only the latter, so a completed
  extend was invisible and every take stayed under the 210 s floor ("16 creates, 0
  extends" was a wrong diagnosis). Fixed 2026-10-31 in `flow_song.py`, pinned by a
  source test; song 02 = 239.3 s, `extended: true`. Keep the 150 s rest before the
  first extend — an extend seconds after its create 429s.
- Karaoke = sum non-vocal stems, not centre-cancel.
- Song 01 live: `ASuxGEvJBlw`, karaoke `SWS1vJJgkow`, three Shorts, playlist
  `PLKlARHtRpKkI`.
- **Competitor scan** (43 channels/1,546 videos): compilations are the watch-hour
  lever; `เลือกเพลงฟังได้` is the strongest title signal (37 winners, 0 losers) and
  needs chapters; titles ≤60 chars, no `| AERIS Music`; our art was too flat
  (luminance std 13-24 vs 22-80) — `_highlight()`+`_vignette()`+`_text_band()`
  fixed it; actives ship ~3.89 uploads/week vs our 1.01. Pinned by `tests/run.py`.
- **Thai text must render:** `music938-1/fonts/NotoSansThai.ttf` (variable);
  **libass needs `fontsdir=`**; both ASS and `covers.py` must raise if it is absent.
- **YouTube cannot swap a file under an id** — upload-then-delete;
  `scripts/replace_video.py` handles it. 6 uploads per Pacific day (reset 07:00 UTC).
- `release.py --next` uploads **private by default** (needs `--public`) and records
  `public: false` even after a later `videos.update` — fix the ledger by hand.
  `work/release-state.json` is tracked: the only record of what is up.

## Keeping the channel active 24h (K, 2026-10-31)

K: "ตรวจสอบช่องเป็นระยะให้ช่องมีความเคลื่อนไหวตลอด24ชั่วโมง". Two mechanisms:

- **Monitor** — OpenHands automation `AX YouTube Activity Monitor`
  (`b4bc39db-4427-4cdc-a4c8-3ba913c2541a`, ACTIVE, hourly cron) runs
  `plugins/yt-activity` (plugin-spec, `runner: script`, **no LLM**): each channel's
  subs/videos/views/newest-upload age into the automation KV store, read back with
  `GET /api/automation/v1/kv/latest?automation_id=<id>`. A rejected token records
  `auth_error` and the run still succeeds. It refetches the plugin from `main` each
  run, so a push changes behaviour.
- **Activity** — `release.py --next --count N --spread H` uploads N items with
  `publishAt` H hours apart, so one batch covers the day; YouTube flips each public
  on its own and **nothing stays running**. 6 uploads per Pacific day.
- **OpenHands secrets hold the YT credentials too:** `POST /api/v1/secrets`
  `{name,value}` with the bearer key; the sandbox injects them as env vars.

## Environment facts that keep costing time

- **A pod recycle is the recurring failure, not quota.** It kills the cloud
  desktop, running jobs, `$HOME`, `/tmp` and pip packages. **Only `/workspace`
  survives.** Never keep state in `$HOME` or `/tmp`.
- **Chromium CDP dies after a recycle** on a stale `SingletonLock`. Clear
  `Singleton*`/`DevToolsActivePort` and relaunch; keep `--remote-allow-origins=*`
  or every CDP websocket 403s.
- **Write access (2026-10-31): `gh auth login --web` device flow.** Unset
  `GITHUB_TOKEN`/`GH_TOKEN` *in the command* (they block the flow), run
  `gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key`,
  give K the code + `https://github.com/login/device`; K authorizes from a phone —
  **PC1 not needed.** Scope `repo`. **AR persists the token** to
  `/workspace/ax-tools/ar-identity/gh-token` (survives a recycle), so a fresh pod
  reads it from there instead of re-running the flow. Push via
  `git remote set-url origin https://x-access-token:$(cat .../gh-token)@...`, then
  reset the remote token-free. AR can also create repos over the API
  (`POST /user/repos`); `aerismusic8-alt/ar-identity` was made this way.
- **No available token carries the `workflow` scope**, so a commit touching
  `.github/workflows/` is rejected. Use an OpenHands automation for scheduled work
  instead of a workflow; K must `gh auth refresh -s workflow` for a CI path.
- Sandbox `GITHUB_TOKEN` is a read-only App token (push/dispatch/fork 403).
  `~/.config/aeris/` (GH App key) is gone. `scripts/push-via-pc1.sh` is blocked:
  PC1's winremote MCP `/mcp` 401s for both `PC1_MCP_TOKEN*` (while `/health` is 200).
- **Sandbox proxy** blocks `POST`/`PATCH` to `www.googleapis.com` (bare 404);
  `GET`/`PUT`/`DELETE` pass. DELETE must carry no body.
- **`multiget-playability-status` reports the caller, not the game** — put a
  control in the same call. **Roblox `BUILD_REF` lies** — the built tree always
  comes from the `ax-arena-roblox-game` branch. Confirm a path exists in the
  provider's own spec before blaming a credential.

## Recovery

- **Sandbox died? Read `ops/AX_RECOVER.md` first** — do not re-learn it.
- Durable vault: `$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py`, KV key `axvault:readme`.
- Missing `ops/` or a daily log? `MEMORY-ARCHIVE.md` + the vault are the sources.
- Full detail: `MEMORY-ARCHIVE.md`, then the daily logs `2026-10-27.md` … `2026-10-31.md`.
