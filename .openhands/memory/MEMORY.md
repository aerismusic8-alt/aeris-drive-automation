# MEMORY — index

**How to use.** Injected index, small on purpose — a long one is truncated from the
top. Rules and pointers only; full detail in `MEMORY-ARCHIVE.md` and the daily logs
beside this file. Past ~6 KB, fold the oldest lines into the archive.

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

AR holds its own identity, kept **outside** the repo (it is public) at
`/workspace/ax-tools/ar-identity/` (survives a recycle): `creds.json` (mailbox
`araeris2909e0@fldubai.com`, mail.tm), `browser-profile/`, `secrets.json`,
`accounts.json`. Tools in `ops/`: `ar_identity.py` (the mailbox over mail.tm —
AR reads its own verification mail), `ar_browser.py`, `ar_accounts.py`.

**Finding:** a free-mailbox signup is captcha-blocked almost everywhere
(archive.org, OSM, Wikimedia, Codeberg, Neocities, PythonAnywhere, GitLab);
sourcehut/Hugging Face reject a disposable domain or datacenter IP. A captcha
signup needs K signed in to the cloud desktop; AR drives that browser and never
types a password.

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
  YouTube's threshold (**1,000 subs AND 4,000 watch-hours/12 mo**). Free lever =
  long-form volume (`compile_album.py`; a 60-min compilation earns 1 h/view vs
  3 min for a song). Quota: 10,000 units/day, 1,600/upload → ~6/day.

## music938-1 — Thai karaoke pack (2026-10-30, detail in archive)

20 songs: lyrics, a **real sung vocal** (Flow Music, free/login-only), a
true-instrumental karaoke mix, cover art, a 1920x1080 word-synced video.

- **429 is account-wide and time-windowed, not parallelism:** `--workers 1`;
  windows UTC 23,0,1,2,6,18; dead zone 07-17. Queue a song with no take first.
- **An Extend renders as `audio__render_edit`, not `audio__extend_song`** — waiting
  only for the latter made every completed extend invisible, so takes stayed under
  the 210 s floor. Fixed in `flow_song.py`, pinned by a source test. Keep the 150 s
  rest before the first extend — an extend seconds after its create 429s.
- Karaoke = sum non-vocal stems, not centre-cancel.
- **Songs 01-09 built** (150 assets in the `media-938` release; `library/` is
  gitignored, the release is the durable copy — `scripts/pull_media.py`). **10-20
  blocked on the Flow Music login**, which is SIGNED_OUT after every pod recycle
  (the profile survives, the cookie does not). K signs in via noVNC
  (`work-1-<host>/vnc.html`), then the batch resumes.
- `setup-pod.sh` used to leave dangling ffmpeg symlinks (unpacked into a deleted
  `mktemp -d`); fixed to unpack under `/workspace/ax-tools/ffmpeg`. Run it after
  a recycle, then `export PATH=/workspace/ax-tools/bin:$PATH`.
- Song 01 live: `ASuxGEvJBlw`, karaoke `SWS1vJJgkow`, three Shorts, playlist
  `PLKlARHtRpKkI`. ch3 = 15 videos; 34 releases pending at 6/day.
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

## Keeping the channel active 24h + promotion (K, 2026-10-31)

- **Monitor** — automation `AX YouTube Activity Monitor` (`b4bc39db-...`, hourly,
  no LLM) writes each channel's stats to the KV store
  (`GET /api/automation/v1/kv/latest?automation_id=<id>`).
- **Activity** — `release.py --next --count N --spread H` schedules N uploads
  `publishAt` H hours apart; YouTube flips each public itself. 6/Pacific day.
- **Daily driver** — automation `AX Music Daily Release` (`86b12141-...`, cron
  `5 7 * * *` UTC, `plugins/music-release`). It **auto-pauses** after 5 consecutive
  failures (always platform cold-start flakes here); re-enable with
  `PATCH /api/automation/v1/<id> {"enabled": true}`.
- **Promotion:** a GitHub Pages site `aerismusic8-alt/site-aeris-music`, refreshed by
  `ops/ar_promo_site.py` from the channel's uploads. Fediverse signup is captcha-dead.
- YT credentials are OpenHands secrets (`POST /api/v1/secrets`), injected as env vars.
- **A plugin automation fetches only its plugin dir** (`AUTOMATION_PLUGIN_ROOT` =
  `plugins/<name>`), not the repo. A plugin needing repo files must fetch them
  itself (`plugins/music-release/scripts/main.py` downloads the tarball).
- **20 sandboxes per day.** Each dispatch *and each retry* burns one; past the cap
  a run is `SKIPPED — "Daily sandbox limit of 20 reached"`, which looks like a bug
  and is not. Retry a flake once or twice, then leave it to the cron. Dispatch:
  `POST /api/automation/v1/<id>/dispatch` (`/runs` is 405; no per-run detail route).

## Environment facts that keep costing time

- **A pod recycle is the recurring failure, not quota.** It kills the cloud
  desktop, running jobs, `$HOME`, `/tmp` and pip packages. **Only `/workspace`
  survives.** Never keep state in `$HOME` or `/tmp`.
- **Chromium CDP dies after a recycle** on a stale `SingletonLock`. Clear
  `Singleton*`/`DevToolsActivePort` and relaunch; keep `--remote-allow-origins=*`
  or every CDP websocket 403s.
- **Write access (2026-10-31):** the sandbox `GITHUB_TOKEN` is read-only (push/
  dispatch/fork 403); `~/.config/aeris/` and `push-via-pc1.sh` are dead. The write
  path is **`gh auth login --web`** (unset `GITHUB_TOKEN`/`GH_TOKEN` *in the
  command*, then `gh auth login --hostname github.com --git-protocol https --web
  --skip-ssh-key`; K authorizes the code from a phone — PC1 not needed). AR
  persists the token to `/workspace/ax-tools/ar-identity/gh-token`; push with
  `git push https://x-access-token:$(cat .../gh-token)@github.com/OWNER/REPO.git main`
  (or the injected `AX_GH_TOKEN`), then reset the remote token-free. **No token
  carries the `workflow` scope**, so use an OpenHands automation for scheduled work.
- **Sandbox proxy** blocks `POST`/`PATCH` to `www.googleapis.com` (bare 404);
  `GET`/`PUT`/`DELETE` pass. DELETE must carry no body.
- **Roblox:** `multiget-playability-status` reports the caller, not the game (put a
  control in the same call); `BUILD_REF` lies — the built tree is always the
  `ax-arena-roblox-game` branch. Detail in `AGENTS.md`.

## Recovery

- **Sandbox died? Read `ops/AX_RECOVER.md` first** — do not re-learn it.
- Durable vault: `$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py`, KV key `axvault:readme`.
- Missing `ops/` or a daily log? `MEMORY-ARCHIVE.md` + the vault are the sources.
- Full detail: `MEMORY-ARCHIVE.md`, then the daily logs `2026-10-27.md` … `2026-10-31.md`.
