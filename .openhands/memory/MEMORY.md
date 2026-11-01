# MEMORY — index

**How to use.** Injected index, small on purpose — a long one is truncated from the
top. Rules and pointers only; full detail in `MEMORY-ARCHIVE.md` and the daily logs
beside this file. Past ~6 KB, fold the oldest lines into the archive.

**Read `.openhands/CHARTER.md` first** — K's standing mandate (2026-10-31) that AR
administers all of K's work in K's place, plus the perpetual loop and the live
priority queue. It is the answer to "what next".

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

**K's rule (2026-10-31): a newly-registered mailbox is NOT for Gemini or Flow.**
Both stay on **K's account `aerismusic8@gmail.com`**; AR's mail.tm address is for
throwaway signups only. `check_login.py` guards this: it prints the signed-in
account and returns `RESULT=WRONG_ACCOUNT` (exit 3) on any other.

**K's standing permission (2026-10-31): "ถ้าใช้ไม่พอสร้างเพิ่มอีกเลย"** — when a free
allowance is not enough to finish, create more accounts. Flow/Gemini remain the
exception: they run on K's account, which only K signs into.

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
- **One loudness contract, one place.** `flow_song._karaoke` used an inline
  **single-pass** `loudnorm=I=-16`, which overshoots (asked -16, delivered -14.4),
  so the karaoke sat at the song's level; song 15's quiet -15.0 master made its
  karaoke +0.6 dB louder. Now routed through `make_song`'s **two-pass** helpers to
  `TARGET_LUFS - KARAOKE_OFFSET_DB`. `flow_song.py <slug> --karaoke-only` rebuilds
  a karaoke from local stems with **no Flow call**; the playwright import is lazy
  so it runs in a bare pod. Fixed `0142f5e`, 356 pass.
- **All 20 songs built** (2026-11-01). **Song 10** (`10-dok-mai-rim-thang`) was
  the last one; the earlier "stuck tab, not content" call was **wrong**. Flow
  rejects song 10's *original lyric text* server-side. The click succeeds —
  `POST /__api/producer/tool-call` → 200 with a `job_id` — and the rejection is
  only in the producer stream: `message {tool_name: audio__create_song}` then
  `error {type: tool_call_failure, message: "Error while streaming parts"}`, no
  clip. **When a Flow create silently yields nothing, read
  `/__api/messages/<job_id>/stream`, not the clips map.** Deterministic (2/2), so
  content not network. A fully-rewritten lyric of the same shape is accepted;
  rewrite the text, do not retry. Fixed `4d2c0be`, 371 pass.
- **The login no longer needs redoing after a fresh sandbox.** It used to: a new
  sandbox gets an empty `/workspace` (a container *recycle* keeps it, a replaced
  sandbox does not), so the chrome profile and every session were gone. `ops/
  login_vault.py save` snapshots the live session cookies over CDP into the
  automation KV store; `restore` puts them back, and `bootstrap.py` calls it after
  it starts the browser. K signs in **once**; after that the desktop comes up
  signed in. Verified live for google + facebook + tiktok. Cookies only, never
  passwords. K signs in via noVNC (`work-1-<host>/vnc.html`) as
  **`aerismusic8@gmail.com`** (K's rule — not AR's registered mail).
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
- **The continuous marketing loop (2026-10-31)** — three layers, so it does not need
  a human each time:
  1. *Measure* `music938-1/scripts/market.py` reads every live video's stats, diffs
     them against `work/market-snapshot.json`, writes `work/market-report.md` (Thai).
     No LLM.
  2. *Promote* `AX Music Marketing Daily` (`03734708-...`, plugin `plugins/market-daily`,
     cron `0 2 * * *`) runs the measure step, refreshes the promo page, commits the
     report + snapshot back to `main`. No LLM.
     **`--root` means the repo root to the plugin but the tree itself to a manual
     run** — `market.py` resolves both now (`resolve_root`). Before 2026-11-01 it
     only accepted the tree, so the plugin's `<repo>/work/release-state.json`
     lookup missed, the report tracked 0 videos, and the run stayed green anyway.
     Always diff the report's numbers against a direct API read.
  3. *Decide* `AX Music Marketing Strategy (weekly)` (`ca7de485-...`, cron `0 3 * * 1`)
     reads the report + `COMPETITOR-ANALYSIS.md` and opens ONE PR. The only LLM layer.
  The report and snapshot are `.gitignore` exceptions on purpose — they are the loop's
  memory. The weekly prompt forbids paid options, workflow edits and merging.
- YT credentials are OpenHands secrets (`POST /api/v1/secrets`), injected as env vars
  **into an interactive session only**. An **automation sandbox gets no user secrets as
  env vars** — a script that reads `os.environ` alone works when a human runs it and
  fails under cron with `missing secret YT_CLIENT_ID`. That is what silently kept
  `AX Music Marketing Daily` and `AX Music Daily Release` red while the release itself
  was fine. Read them through **`ops/ax_secrets.get_secret`** (env first, else
  `GET {AGENT_SERVER_URL}/api/settings/secrets/{name}` with `X-Session-API-Key`; cloud
  fallback `/api/v1/sandboxes/{SANDBOX_ID}/settings/secrets/{name}`). This is the same
  route `plugins/yt-activity` always used, which is why it alone stayed green. Fixed
  `0245f45`; pinned by `test_automation_secret_fallback`.
- **A plugin automation fetches only its plugin dir** (`AUTOMATION_PLUGIN_ROOT` =
  `plugins/<name>`), not the repo. A plugin needing repo files must fetch them
  itself (`plugins/music-release/scripts/main.py` downloads the tarball).
- **20 sandboxes per day.** Each dispatch *and each retry* burns one; past the cap
  a run is `SKIPPED — "Daily sandbox limit of 20 reached"`, which looks like a bug
  and is not. Retry a flake once or twice, then leave it to the cron. Dispatch:
  `POST /api/automation/v1/<id>/dispatch` (`/runs` is 405; no per-run detail route).

## Channel build-out: profile, Stories, compilation, Shopee (2026-11-01)

- **Profile**: `scripts/brand.py` → banner 2560×1440 (text inside the 1546×423
  safe strip) + avatar 800×800; `scripts/apply_brand.py` uploads the banner via
  the API. **The avatar has no API** — set it in the signed-in Studio profile
  editor. Verified live; avatar URL changed.
- **Stories**: `scripts/make_stories.py` → 21 cards (1080×1920);
  `scripts/post_stories.py` posts to Facebook Stories (21/21). YouTube has no
  Story, so `scripts/post_community.py` posts to the Posts tab — entry point is
  the **create menu** ("สร้าง" → "สร้างโพสต์"), not the `?show_create_dialog=1`
  URL, which opens the dialog only intermittently.
- **The watch-hour lever is the long compilation with chapters**, not the
  singles: a 60-minute watch earns a whole watch-hour, a 3-minute song 0.05 of
  one. `compile_album.py` builds it (15 tracks ≈ 57 min, title
  `...(เลือกเพลงฟังได้)`). **Live: `3Yz2jxZnKmM`.**
- **Bug fixed**: `compile_album.render()` overwrote `compilation.txt` with a
  bare tracklist after `main()` wrote the chaptered description, so the upload
  lost every timestamp — the exact signal the title promises. Re-uploading the
  description (no duplicate) restored 15 chapters. Pinned by a test.
- **`upload_compilation.py --watch --upload`** waits for the render then uploads,
  so a recycle during the ~14-minute ffmpeg run cannot lose it.
- **Shopee rail — LIVE 2026-11-01**: `channel/monetization.json` is the single
  source for outbound links; `scripts/monetize.py` builds the block and
  `release.py` appends it to every description. `shopee_affiliate` =
  `https://th.shp.ee/6hv2uk89` — a Shopee **share-marker link, not an affiliate
  link** (302s to `sv.shopee.co.th/me/1469892103?fromShareLink=share-marker`).
  `scripts/apply_monetize.py` backfills the footer into existing **uploads and the
  3 channel playlists** (playlists must be listed by `channelId` — Liked/Uploads
  return 400 "playlist type not supported"). K's Shopee identity is private and
  lives outside this public repo in `/workspace/ax-tools/ar-identity/accounts.json`.
  Rates: **2.00% direct / 0.60% indirect**, cap 225 THB/order. See `channel/SHOPEE.md`.
- **Shopee attribution ("โฆษณาอะไรไปที่ไหน")**: a `th.shp.ee` short link **strips
  `sub_id`** (verified live), so one link cannot say which surface earned. Mint
  `s.shopee.co.th/...?sub_id=<label>` links in the affiliate dashboard and put them
  in `shopee_links`; `monetize.link(surface)` prefers those and falls back to the
  plain link. K reads results at **affiliate.shopee.co.th → Report**, filtered by
  Sub ID (or the app → ฉัน → โปรแกรม Affiliate → คำสั่งซื้อ). Read orders/commission,
  not clicks.
- **Shopee login is a K-only action**: K's account is `navintas` /
  `kongkeat.p3@gmail.com`; the cloud desktop's Google account is
  `aerismusic8@gmail.com` — **different account**, and Shopee's Google button is an
  `oauth2/authorize` **redirect** (not a popup) that drops the `next=` target. Use a
  one-time **QR login from K's phone**.
- **Channel conversion surfaces** (all free, all done 2026-11-01): trailer =
  the 57-min compilation `3Yz2jxZnKmM`; home sections "ยอดนิยม" + a playlist row
  (`channelSections` — there were none); compilation in the song playlist.
- **Wrong-render backlog self-heals**: `scripts/pending_replacements.py` runs
  **before** `daily_release.py` inside the `music-release` plugin, because a
  replacement spends the same upload slot a release does. `replace_video.py`
  fetches media from the `media-938` release and handles Shorts.
- **No K blockers left.** The old two (Analytics API, comment scope) are dead
  ends, not asks: the ch3 OAuth client is **NATIVE_DEVICE**, so `youtube.force-ssl`
  is refused at the device endpoint and a loopback redirect is refused too, and
  `aerismusic8@gmail.com` cannot even open Cloud project `888023422403`. Route
  instead: the **cloud desktop** is signed in as the owner, so
  `music938-1/scripts/studio_web.py` reads analytics and posts comment replies by
  driving YouTube Studio over CDP. Verified live (reply posted 2026-11-01).
  `scripts/desk_daily.py` = the one browser-side admin pass (comments →
  analytics → crosspost FB/TikTok → Thai report).
- **Four surfaces** (K: "yt fb tk shoppe"), all in `channel/monetization.json` and
  in every footer: YouTube `@aerismusicth`, Facebook **Page** `61595890900382`
  (created 2026-11-01; the personal profile `61596276533369` cannot be branded),
  TikTok `@aeris.music4`, Shopee `th.shp.ee/6hv2uk89`. Crosspost = 120/120.
- **Plan + rules**: `channel/GROWTH.md` (calendar, the scan's constraints:
  titles ≤60 chars, no `| AERIS Music`, cover luminance std ≥22, chapters on
  every compilation).

## Environment facts that keep costing time

- **A pod recycle is the recurring failure, not quota.** It kills the cloud
  desktop, running jobs, `$HOME`, `/tmp` and pip packages. **Only `/workspace`
  survives.** Never keep state in `$HOME` or `/tmp`.
- **Python deps must live under /workspace.** A recycle wipes the `$HOME`
  site-packages and playwright/Pillow/numpy/pythainlp vanish. Install with
  `pip install --target=/workspace/ax-tools/pylibs ...` and add a `.pth`
  (`echo /workspace/ax-tools/pylibs > <site>/ax-pylibs.pth`) so a plain
  `python3` finds them. `music938-1/scripts/setup-pod.sh` does this now.
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
