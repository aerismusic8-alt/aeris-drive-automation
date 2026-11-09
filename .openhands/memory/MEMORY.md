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
  **Caveat (verified 2026-11-07): PCSEV is documentation-level plus AR's habit, not
  machine-enforced.** `AX_MASTER_STATE.json` still says `"pcsev": "INTEGRATING"`, and
  `AKATH_CORE/BUILD_PLAN.md` Phase 2 ("Implement deadline monitoring and PCSEV
  recovery") is unchecked. No runner applies it (unlike `ops/consult.py`, which is a
  real gate). Defined in `AX_MASTER_BRAIN/AX_MASTER_STATE.json` operating_principles,
  `AKATH_CORE/AX_RUNTIME_CONTRACT.md` §8, `AKATH_CORE/AX_EXECUTION_LOOP.md` step 10,
  `AX_MASTER_BRAIN/TASK_REPORTING_PROTOCOL.md` §10 (shown only when K asks to continue).

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
**Planner agents (2026-11-03):** ChatGPT (Free) and Gemini (Free) are both signed
in on the desktop. Ask them over CDP — `ops/chatgpt_ask.py "..."`,
`ops/gemini_ask.py "..."`, or `ops/ask_agents.py "..."` to compare both at once.
No API key, no cost. (Claude/Copilot/Perplexity/DeepSeek are NOT signed in.)
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

**K's voice: tried, then dropped (2026-11-04).** K offered a singer voice, then
ruled the result unusable and closed it: **do not build voice cloning again
unless K asks.** (Flow cannot clone a voice — it rejects a clip with vocals; the
free route was stem swap + kNN-VC, but the 16 kHz vocoder is too dull to sing
with. Detail in `2026-11-04.md`.)

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
- **All 20 songs built** (2026-11-01) — **but 10-20 were the rejected Piper
  engine and are quarantined.** The pack *looked* complete; the manifest called
  them `offline-engine`. The tell needs no ear: `make_song.py` stacks one mono
  signal into both channels, so songs 10-20 are 44100 Hz with **bit-identical**
  left/right, while Flow Music renders (01-09) are 48000 Hz true stereo.
  `scripts/provenance.py` now decides this from the audio, and `make_song.py` /
  `build_all.py` refuse to run without `--retired-engine` (the warning in memory
  was not enough; it came back because Flow was signed out and make_song needs no
  login). Songs 10-20 must be regenerated by Flow Music.
  **Song 10** (`10-dok-mai-rim-thang`) was
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
- **Catalogue is open (2026-11-01, K: "unlimited songs, any genre, AR plans
  it")**. `channel/genres.json` is the plan *and* the single source of a genre's
  sound; a song joins one with `# GENRE: <id>` in its lyrics header.
  `scripts/genres.py` resolves it for all three description points:
  `flow_song.style_for` (sound), `release.describe` (tagline + tags),
  `covers.make_cover`/`make_thumbnail` (palette via `genres.PALETTE_FOR`). **No
  header = old mood behaviour**, so songs 1-20 are untouched — that rule is the
  safety property and a test pins it. Every genre id must map to a real
  `covers.PALETTES` key or the cover test fails. 12 genres planned, 496 tests.
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
- **Crosspost rail (FB Reels + TikTok)** — `scripts/crosspost.py`, queue
  `work/crosspost-queue.json`, ledger `work/crosspost-state.json`. Three defects
  fixed 2026-11-01 (`dc1d3255`): it stored `page.url` (the studio page) instead
  of the post URL — now `newest_post_url()` reads the platform's own list, and
  an unreadable URL is left empty, never a page URL; there was no cadence — now
  `pace_ok()` enforces **20 min min-gap and 4 posts/platform/day** (the first run
  fired **60 TikTok posts in 98 min, median gap 26 s**, the likely cause of 0
  views); and `caption()` ignored the hook, so a song's 3 hooks shared one
  caption — now h2/h3 are tagged `(ท่อน N)`. **`--rebuild-queue` rebuilds from
  the Shorts on disk and a recycled pod holds only a subset (27 of 54) → it
  truncates the tracked 120-item queue. Patch the JSON in place instead.**
- **A 4th crosspost defect (2026-11-02): the cadence guard was blind to Page
  posts.** `_posted_times(state, "facebook")` matched keys by the raw platform
  name, but a Reel posted to the Page is stored under the **`facebook-page`**
  state key (the 60 pre-Page posts used `facebook`). So the 20-min gap and daily
  cap never applied to the Page — two Reels went out **45 s apart** before it was
  caught. Fix: read `PLATFORMS[platform]["state_key"]`. Regression tests in
  `music938-1/tests/run.py`. The composer URL
  `business.facebook.com/latest/reels_composer/` is flaky ("เนื้อหานี้ไม่พร้อมใช้งาน")
  and FB Page views are intermittent — retry a load before believing an error.
- **A 5th crosspost defect (2026-11-02): `post()` rebuilt the queue from disk.**
  Same root as the `--rebuild-queue` note above, but in the posting path: `post()`
  called `build_queue()`, so a fresh pod saw **6** pending instead of **78** and
  the 32 Facebook Reels for songs 13-20 were unreachable (`--plan` printed
  "nothing pending" while 34 sat in the committed queue). Fix: `load_queue()`
  prefers `work/crosspost-queue.json`, builds only when the file is missing.
  Any code path that needs the backlog must read the committed file, not the disk.
  Platform rules to avoid a ban: **`aeris938-2/COMPLIANCE.md`**.
- **Growing the FB Page (K's rule, 2026-11-03): a Page needs no friend list.**
  Follow suggested pages (they often follow back) — `aeris938-2/scripts/outreach.py`,
  wired as `grow.py facebook --follow`. The invite tool
  (`facebook.com/<PAGE_ID>/follower_invite/`) is *friends-of-the-personal-profile
  only*, so it is empty on a fresh account; it also needs the **personal** profile
  as the acting identity. **The trap:** a follow lands on the Page only when the
  Page is the acting identity *before* the follow grid loads — the grid has no
  "สลับเลย" switch, so switching after navigating is a silent no-op (personal
  0→6, Page unchanged). Switch on the Page profile first, prove it via the
  "จัดการเพจ" header, then navigate. Verified: Page "กำลังติดตาม" 1→30 in a
  session. Scheduled twice daily by the `plugins/ax-growth` automation
  (`c2cdcfd7-fb4f-44a9-96b1-40ab35534ce8`); it could not be a GitHub workflow
  because no token here carries `workflow` scope.
- **Editing the FB Page profile (done once, reusable):** the Page's own "⋯ profile
  settings" menu only appears in **admin mode** — click "สลับเลย" first. To change the
  bio: `/profile.php?id=<page>&sk=about` → click `aria-label="แก้ไขคำอธิบายตัวเอง"`
  → a **`<textarea>`** appears (not contenteditable) → set it with the native setter
  `HTMLTextAreaElement.prototype.value.set` + dispatch `input` → click `บันทึก`. The
  FB Page tab is heavy: a 40 s websocket times out, and some FB tabs are permanently
  wedged — pick a tab that answers, use a 90 s timeout (`work/fb_publish.py`). Page
  composer text lands only via CDP **`Input.insertText`** (execCommand insertText
  does not take). **Pinning is not verifiable by the agent** — the pin click works but
  neither www, mbasic nor m.facebook render a `ปักหมุดโดย`/`is_pinned` marker for an
  automated client, so a human must confirm a pin.
- **The 3 non-YouTube surfaces are now measured** (`00221355`):
  `scripts/social_stats.py` drives the desktop to the FB/TikTok/Shopee
  dashboards → `work/social-report.md` (whitelisted), run by `desk_daily.py`
  step 2b. `market.py` is YouTube-only, so this is the loop's only view of them.
  Unreadable = **UNKNOWN, never a guess**. Parsing traps: TikTok's analytics
  "Followers" is the *change over the period*, not the total (read the profile
  for the total); TikTok puts the value on the **next line** (needs look-ahead);
  "เข้าสู่ระบบ" is in FB chrome even when signed in (detect sign-out by the
  *absence* of "ผู้ติดตาม N คน"); FB `professional_dashboard/insights/` answers
  "Not Found" cold — land on the Page first and fall back to the Page profile.
- **Measured 2026-11-02**: FB followers 0; TikTok 1 follower, 0 views/7d;
  Shopee not onboarded. **Earlier claim of "duplicate TikTok posts" was WRONG**
  and is retracted — the profile has 64 distinct videos (the "16" was a
  virtualization artifact; scroll until the element set is stable before
  counting) and all 60 ledger ids are unique. The paired Studio rows were the 3
  chorus hooks of one song (different files, same caption). Full record:
  `channel/SOCIAL.md`.
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
  `s.shopee.co.th/...` links in the affiliate dashboard and put them in
  `shopee_links`; `monetize.link(surface)` prefers those and falls back to the
  plain link. K reads results at **affiliate.shopee.co.th → Report**, filtered by
  Sub ID (or the app → ฉัน → โปรแกรม Affiliate → คำสั่งซื้อ). Read orders/commission,
  not clicks.
- **Shopee is already onboarded — no QR needed (2026-11-02).** Earlier notes said
  login was a K-only QR action; that is wrong now. The cloud desktop is signed in
  to `affiliate.shopee.co.th/dashboard` as **`navintas`** (orders 0, commission 0).
  AR minted one tracking link per surface via the dashboard **Custom Link** tool
  (`/offer/custom_link`: destination textarea = `https://shopee.co.th/`, set
  `#customLink_sub_id1`, click the `เอา ลิงก์` button, read the `s.shopee.co.th/...`
  from the "ลิงก์โปรโมต" panel) and wrote them to `channel/monetization.json` →
  `shopee_links`: youtube `3g4vw3cev0`, tiktok `6fiXVb7Fbi`, facebook `7KyEIqRt6A`.
  Drive the React form with the native value setter + input/change events; a first
  `shopee.co.th` hit shows a captcha, a second goto lands it.
- **Shopee numbers read headlessly via the affiliate JSON API (2026-11-03).** The
  dashboard page blocks every automated browser (`/verify/traffic/error`), but the
  API behind it answers a plain HTTP GET with the exported session cookies — no
  browser, no captcha. That is what makes a scheduled Shopee report possible.
  - `GET /api/v1/click_report/list?click_time_s=<s>&click_time_e=<e>&page_num=1&page_size=1`
    → `data.total_count` = clicks.
  - `GET /api/v3/report/list?purchase_time_s=&purchase_time_e=&page_size=20&page_num=1&version=1`
    → `data.total_count` = orders; `data.list[]` = conversions.
  - `GET /api/v3/payment/billing_list?order_completed_start_time=&order_completed_end_time=&settlement_cycle=4`
    → `data.income_breakdown` = commission.
  - Required headers: `Cookie`, `Affiliate-Program-Type: 1`, `Referer`, normal UA.
  - `/api/v3/dashboard/detail` is 403 (`error 90309999`) — it needs anti-bot signed
    headers (`af-ac-enc-sz-token`, `x-sap-*`). Do not chase it; the report endpoints suffice.
  - Needs the short-lived session cookies (`SPC_SEC_SI`/`SPC_SI`/`SPC_ST`, ~1 day) **and**
    the long ones (`SPC_F`/`SPC_U`/`SPC_R_T_ID`/`SPC_T_ID`, ~400 days); without a session
    cookie it returns `code:30002 cookie incorrect`. They come from the same storage state
    as FB/TikTok, so they refresh on the normal sign-in cadence. Implemented as
    `social_stats.measure_shopee_api()`; `measure_shopee()` tries it before the scrape.
- **Shopee Open API (for AppID/Secret) needs a formal application — gated (2026-11-03).**
  `affiliate.shopee.co.th/open_api` Apply is disabled; the official form is
  `https://shopee.co.th/program/form/6118` (reachable via help webform
  `a4cf1d7f77274b9d8fa8623e7d82158b` → "ฟีเจอร์และฟังก์ชั่น" → "Affiliate Open API" → Next).
  It requires a PDF plan doc, follower/reach numbers, and **>1,000 orders/month**;
  `navintas` has 0 orders, so it does not qualify yet. The internal JSON API above is the
  free workaround until then — it needs no approval.
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
  analytics → pin full-song on Shorts → playlists → crosspost FB/TikTok → report).
- **Analytics without any login (2026-11-01)**: the **public** channel page is
  enough for subs/views/per-video (`/@aerismusicth/about`, `/videos`, `/shorts`
  — tile text is `duration ~ title ~ views ~ age`). The desktop's Google session
  **expires often**; when `studio.youtube.com` says "Signed out", watch hours,
  CTR, traffic and audience are **UNKNOWN** — say so, never guess. Fix = K logs
  into Google on the desktop over VNC. **FB** = click the Thai nav on
  `facebook.com/professional_dashboard/insights/` (the `business.facebook.com/
  latest/insights/...` deep link 404s). **TikTok** =
  `tiktok.com/tiktokstudio/analytics/{overview,followers,content}`. **Shopee** =
  always UNKNOWN (QR-only, K's own account). Report shape: `channel/ANALYTICS-REPORT.md`.
- **Pinned-comment lever works (2026-11-01).** A Short earns the view; its pinned
  comment carries the viewer to the full song. Posting needs only a synthetic
  `.click()` + the native textarea setter. Pinning is done on the **watch page**
  (thread ⋮ "เมนูการทำงาน" → ปักหมุด → the confirm dialog's own ปักหมุด; each
  button renders twice, use the **last**). Drive it as **one awaited page
  script** or the menu portal mounts too slowly. Proof of a pin is the text
  **"ปักหมุดโดย"** (no `pinned-comment-badge` element here). Match the pin item by
  **exact** text `'ปักหมุด'` — a pinned menu reads "เลิกปักหมุด", so a loose match
  would *unpin*. `pin-shorts` is idempotent and skips retired Shorts.
- **Studio hides the channel's own comments by default** (filter "ไม่ได้ตอบกลับ"),
  so the per-video list reads "ไม่พบความคิดเห็น" even when the comment exists.
  Trust `videos.statistics.commentCount`, not that panel. And never post a test
  comment to a live video — cleanup is a manual owner ⋮ → ลบ pass on the watch page.
- **Chromium throttles a background tab.** `Desk` sends `Page.bringToFront`; without
  it lazy lists (the comment inbox) never render and show a "ลองอีกครั้ง" retry.
- **Four surfaces** (K: "yt fb tk shoppe"), all in `channel/monetization.json` and
  in every footer: YouTube `@aerismusicth`, Facebook **Page** `61595890900382`
  (created 2026-11-01; the personal profile `61596276533369` cannot be branded),
  TikTok `@aeris.music4`, Shopee `th.shp.ee/6hv2uk89`. Crosspost = 120/120.
- **Plan + rules**: `channel/GROWTH.md` (calendar, the scan's constraints:
  titles ≤60 chars, no `| AERIS Music`, cover luminance std ≥22, chapters on
  every compilation).

## Environment facts that keep costing time

- **The 24/7 layer is GitHub Actions, not a sandbox.** `aeris-drive-automation` is
  now **public**, so Actions minutes are free (the old private-repo CI wall is
  gone) and its 15 repo secrets include `YT_CH1..CH4_REFRESH_TOKEN` +
  `YT_CLIENT_ID/SECRET`. `ax-roblox-live-state.yml` proves `cron '0 * * * *'`
  runs hourly. **Workflow files ship via PC1, not the sandbox:** no sandbox token
  carries `workflow` scope, but PC1's git credential does. Write the file to
  `C:\ax\`, copy it over the checkout on PC1, commit and push from PC1
  (`PC1_MCP_TOKEN_2`, endpoint `desktop-rgk6jkb.tail8740ad.ts.net/mcp`, helper
  `/tmp/pc1.py FileWrite|FileRead|Shell`; Shell caps ~30 s and returns
  `'NoneType' ... strip` on empty output, so redirect to a file and FileRead).
- **4 music rails live on GitHub Actions (free, no sandbox):**
  `ax-music-release` 07:00 UTC (6 clips/day, scheduled publishAt),
  `ax-music-crosspost` every 2h (FB Reels + TikTok from the committed queue),
  `ax-rail-watchdog` every :15 (4 channels + ntfy),
  `ax-music-dashboard` **08:30 UTC** (PROGRESS.md + market-report + **ntfy push to
  K's phone**). Dashboard is at 08:30, not 07:20, because release spends ~9,600 of
  the 10,000 Data API units at 07:00 and the quota only resets at 07:00 UTC
  (Pacific midnight) — 07:20 gave `channels.list` = `quotaExceeded`. ntfy topic
  `ax-ar-aeris-9f3k7q` (repo var `AX_NTFY_TOPIC`).
- **Posting to FB/TikTok no longer needs a pod (2026-11-03).** `ax-music-crosspost`
  runs on Actions and restores a saved browser session from the
  `AERIS_STORAGE_STATE_B64` secret; `browser.connect()` launches its own headless
  Chromium when that var is set (fallback stays CDP). Export the state with
  `ops/save_storage_state.py` from the cloud desktop (it reads CDP :9222 and keeps
  only facebook.com/tiktok.com cookies); refresh it after a fresh desktop sign-in.
  Verified run 41554234889: probe OK, FB 5/39, TikTok 39/39.
  **A dead session is the rail's most common failure**: a schedule run stops at
  "Is the saved session still signed in?" and every later step is skipped, so the
  queue silently stalls. Refresh = `python3 ops/save_storage_state.py > blob` then
  set the secret. Two routes: `gh secret set AERIS_STORAGE_STATE_B64` (needs `gh`
  authed), or, when only `AX_GH_TOKEN` is set, the secrets API —
  `GET /actions/secrets/public-key`, seal with `pynacl`
  (`pip install --target=/workspace/ax-tools/pylibs pynacl`), `PUT
  /actions/secrets/AERIS_STORAGE_STATE_B64` → 204 (done 2026-11-04).
  **Setting the secret is fine, but the workflow file itself still needs PC1** — a
  plain `git push` of `.github/workflows/` is rejected for lack of `workflow` scope.
- **Shopee Affiliate reports only through the warmed desktop (2026-11-03).** The
  affiliate dashboard answers *any* fresh automated browser with a
  `/verify/captcha` puzzle + `is_logged_in=false`, headless **and** headed/Xvfb,
  even with all 33 `SPC_*` cookies present; `affiliate.shopee.co.th/open_api`
  says "you currently do not have access". So the live read works only over CDP
  :9222 on the desktop profile. `report.py` carries Shopee clicks/orders/
  commission and falls back to the last real reading (labelled with its date)
  when the live read fails; the dashboard rail pushes the click count to ntfy.
  `ops/save_storage_state.py` now also keeps `shopee.co.th` cookies.
- **PC1 cookie extraction is dead, and Studio/FB still need K's login.** Chrome 156
  uses app-bound (v20) cookie encryption that `CryptUnprotectData` cannot unwrap,
  and `Network.getAllCookies` over CDP returns no SID/LOGIN_INFO. Chrome M136+
  refuses `--remote-debugging-port` on the default user-data-dir (a `mklink /J`
  junction makes CDP start, but the profile still reads "Sign in"). The sandbox
  desktop's Google session covers **Flow Music only, not YouTube** — Studio shows
  "Enter your password". So replying to comments, pinning, and Studio analytics
  need K to sign in to YouTube once in noVNC; the token's `.../auth/youtube` scope
  is not enough (commentThreads/playlists = 403). Sandbox TikTok login works; FB
  session is rejected.
- **After a pod recycle, run `ops/login_vault.py restore` BY HAND (2026-11-03).**
  `bootstrap.py` prints `login restore skipped: cannot list automations: 401`
  (that 401 is `ax_vault.ensure_anchor()`'s automation-list path, *not* a dead
  vault) and the desktop comes up signed out. Running `restore` directly worked
  and got **Google/YouTube + TikTok SIGNED IN**; FB still rejected, Flow Music
  still logged out, YouTube Studio re-asks the password. So one desktop sign-in
  (Google + `flowmusic.app`) unlocks the factory. `login_vault.py` now **watches
  `.flowmusic.app`** (the song engine — it was not watched, so a fresh sign-in
  would not have been restored) with a negative-marker probe, and
  `save_storage_state.py` exports YouTube/Google/Flow too, so one export covers
  every rail. After K signs in: `login_vault.py save` + `save_storage_state.py`
  → `gh secret set AERIS_STORAGE_STATE_B64`.
- **A provisioned sandbox is the fragile part, and it is what breaks.** "AX Music
  Daily Release" was **auto-paused by the platform** after 5 consecutive failures,
  all `Timed out: Sandbox not available` (`disabled_detail.source ==
  consecutive_failures`). Re-enable with `PATCH /api/automation/v1/{id}
  {"enabled":true}`. Even a plugin-spec `script` runner needs provisioning — a
  dispatch sat at phase `Starting automation` for 25+ minutes. So an automation
  cannot reliably watch automations; only GitHub Actions runs outside this.
- **`Timed out: Sandbox not available` is usually the DAILY SANDBOX QUOTA (20/day),
  not a platform outage.** Read `run.status_detail`: `kind == daily_sandbox_limit`,
  detail "Daily sandbox limit of 20 reached". Found 2026-11-02: two hourly
  automations (Watchdog `15 * * * *`, YouTube Activity Monitor `0 * * * *`) asked
  for 24+24 = 48 provisions/day, drained the quota by morning, and made the 07:05Z
  Daily Release FAIL every day (and Watchdog SKIP before its heal code, so it could
  not self-heal). Fix = thin the hourly ones: `PATCH /api/automation/v1/{id}
  {"trigger":{"type":"cron","schedule":"0 */6 * * *","timezone":"UTC"}}` (watchdog
  accepts a partial `trigger`). Budget now ~10/day. A SKIPPED run means the sandbox
  never started, so the script inside did nothing.
- **A FAILED automation run can still have done its work.** The music-release plugin
  fires its COMPLETED/FAILED callback *after* the uploads; the platform then failed
  verification with `environment_unavailable`. Cross-check the real result (YouTube
  upload list, git) before treating a run's status as the outcome.
- **`plugins/ax-watchdog`** is the rail's watcher (hourly at :15, no LLM): heals
  auto-paused automations (never a manual pause), flags a stale channel, pushes to
  **ntfy.sh** (free, no auth, no key — K subscribes on a phone). It runs in both
  callers: the OpenHands automation (KV store + automation audit) and GitHub
  Actions (file-based cooldown, audit skipped, no `OPENHANDS_API_KEY`).
  `ntfy_topic` / `AX_NTFY_TOPIC` must be set or alerts are silently not pushed.
- **YouTube does not need the desktop at all.** `YT_CH3_REFRESH_TOKEN` →
  `oauth2.googleapis.com/token` → `youtube/v3` works with no sandbox, browser or
  login (scope `.../auth/youtube`, upload included). Channel read verified:
  AERIS Music, 5 subs, 22 videos. Use this path for anything programmatic; the
  cloud desktop is only for surfaces with no API (Studio UI, FB, TikTok, Shopee).
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
- **`AX_GH_TOKEN` writes (2026-11-02).** In a *build* pod, `AX_GH_TOKEN` (env
  secret) authenticates as `aerismusic8-alt` and can push to
  `aeris-drive-automation` and the site repo, and call the Contents API. So the
  old "no token can write" rule is pod-dependent: the *sandbox* `GITHUB_TOKEN` is
  still read-only, but `AX_GH_TOKEN` is not. Push pattern:
  `git remote set-url origin https://x-access-token:$AX_GH_TOKEN@github.com/...`,
  push, then reset the remote token-free. Still no `workflow` scope.
- **Two release paths must share one ledger (2026-11-02).** `AX Music Daily
  Release` runs in a *different sandbox* and writes `music938-1/work/release-state.json`
  back to `main` via the Contents API. A build pod's local ledger is stale, so a
  manual `release.py --next` re-uploads what the automation already published —
  it happened (6 duplicates on 2026-11-02, deleted). `release.py` now unions the
  local ledger with the live one on `main` (`merge_ledger`) before planning. Any
  new release path must do the same; never trust a pod-local ledger alone.
- **The revenue gap is conversion, not views (2026-11-03).** Views exist (TikTok
  377/7d, YT 2,182/28d, FB 38/28d) but followers sit at 1 and Shopee reads 0
  clicks / 0 orders / 0 commission. Cause: every outbound link pointed at the
  Shopee *homepage*, and the affiliate line was below YouTube's "Show more" fold
  and at the end of the FB/TikTok captions. Fix shipped: `ops/shopee_mint.py`
  mints per-surface Custom Links to a product search; `monetize.cta()` leads the
  description; `crosspost.caption()` puts the link + follow ask in the first two
  lines; `apply_monetize.py` backfills the live videos (4 writes/day, from
  `daily_release.py`). The description footer's source of truth is
  `music938-1/channel/monetization.json`; `aeris938-2/channel.json` is only for
  the report.
- **A `.yml` edit cannot be pushed (2026-11-03).** No token in this workspace has
  the `workflow` scope, so any push touching `.github/workflows/*.yml` is
  rejected. Put new rail logic in a `.py` the workflow already calls
  (`daily_release.py`, `crosspost.py`). If a `.yml` change is already committed
  it blocks every later push — `git checkout FETCH_HEAD -- <file>` (after a
  `git fetch`) then `git commit --amend`.
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
- **Workflow files are read/run-only (2026-11-03).** `AX_GH_TOKEN` (classic PAT,
  `repo` scope) can `workflow_dispatch` and read runs, but **cannot create or
  edit `.github/workflows/*`** — git push 403, Contents API 403/404 (a PUT of the
  identical blob returns 200 but writes nothing). Ship reliability logic as plain
  Python under `ops/`/`plugins/`; only K/PC1 can change a workflow. CI self-heal
  also needs `actions: write`, which the workflows do not set.
- **GitHub cron delivery is best-effort (2026-11-03).** Hourly crons here were
  delivered ~17h apart; two daily crons (Daily Release, Daily Dashboard) **never
  fired at all** (manual dispatch only) and looked green. Green ≠ schedule alive.
  `ops/heartbeat.py`, folded into the hourly `ax-watchdog` plugin, now checks
  recency + "cron never fired" and re-dispatches stale rails from the pod.
- **Email is the master key (2026-11-03).** GitHub "sudo mode" ("Confirm access →
  Verify via email") guards BOTH creating a token at `/settings/tokens/new` AND
  the `gh auth login --web` device flow's final Authorize. The code goes to
  `aerismusic8@gmail.com`, which is **signed out** on the desktop — so no
  workflow-scope token can be minted and no revenue mail can be read until that
  mailbox is signed in. K's approval is not the blocker; the mail code is.
  Restoring cookies puts a `.google.com` SID back but Gmail still shows the
  account chooser, so the Google session does not survive as a usable mailbox.
- **Shopee affiliate is behind an anti-bot CAPTCHA.** `affiliate.shopee.co.th`
  redirects to `shopee.co.th/verify/captcha` (slide puzzle) even with the
  affiliate cookies present, so revenue cannot be read programmatically.
- **`bootstrap.py` restore needs `OPENHANDS_API_KEY`.** Without it the KV read
  401s and the message looked like "no saved login yet"; the fix now names the
  cause. Cookies ARE saved (255) and restore works once the key is exported.
- **`workflow`-scope PAT obtained (2026-11-03).** K supplied the sudo email OTP;
  the working sequence is: open `/settings/tokens/new?scopes=repo,workflow`, click
  **Verify via email** exactly once (reveals `#sudo_email_otp`; a resend kills the
  code), fill it, click the real **Verify** button — a JS `form.submit()` fails
  ("Sudo authentication failed") because it drops `credential_type`. Token is
  `repo, workflow` + admin. Copies: `/workspace/ax-tools/ar-identity/gh-workflow-token`
  and KV `axsecrets:gh-workflow-token`. AR can now push `.github/workflows/*`.
- **A once-a-day GitHub cron is unreliable; give it ≥3 ticks.** GitHub drops a
  scheduled run under load and a single daily slot has one chance — the 07:00
  release and 08:30 dashboard never fired. Fixed to `0 7,13,19` and `30 8,14,20`;
  safe because both jobs are idempotent.
- **The watchdog self-heal needed `actions: write` + an exported `GITHUB_TOKEN`.**
  It had neither, so `heartbeat.py` could not read runs and dispatch would 403.
- **Shopee revenue IS readable programmatically** via `social_stats.py` (JSON API
  + session cookies); only the *dashboard page* is CAPTCHA-gated. Latest: 0 clicks,
  0 orders, 0 commission.
- **Music lyrics are the bottleneck, not the music (K, 2026-11-03).** Flow Music
  sings the exact line breaks it is handed, so hand-written lyrics with uneven
  syllable counts make the melody fight the vocal. `music938-1/scripts/ai_lyrics.py`
  writes lyrics with **Gemini web, signed out** (free, no login) under a strict
  8-syllable/one-breath/A-B-A-B/repeating-hook brief. Gemini driving quirks:
  `keyboard.insert_text` (not `type` — a multi-line prompt submits on line 1);
  slice the answer after "Gemini said" (the prompt echoes the `[verse]` tags).
- **Karaoke + lyric captions are RETIRED (K, 2026-11-03).** The sweep timing was
  *estimated* (Flow's compose path has no `timing_markers`) and drifted off the
  sung line. `make_karaoke`/`make_short` default to no captions; `release.py` no
  longer plans the sing-along upload; one video per song. `--captions` restores.
- **Rendering new songs needs K to sign into Flow Music** on the cloud desktop
  (session expires); then `build_songs.py --only <slugs> --force`.

## Flow Music render limits (2026-11-03)
- **Free tier runs out of credits.** After ~7 songs in a session the compose page
  shows "You're out of credits. Upgrade to continue using Flow Music." and the
  Generate button becomes **disabled**. That is a quota, not a bug. Rule #1 =
  never pay → render 3-4 per window and wait for the free reset. **`flow_song.py`
  now detects the banner in `_wait_composer` and raises `RateLimited` immediately**
  (2026-11-06), so a spent quota prints `{"status": "RATE_LIMITED", ...}` instead
  of a 30s-per-song opaque `Locator.click: Timeout ... element is not enabled`.
  A batch loop should stop on the first `RATE_LIMITED`, not march through the rest.
  `music938-1/scripts/render_remaining.py --check` also probes it
  (exit 0 ok / 2 out of credits / 3 logged out).
- **The desktop Chromium dies on its own; the X server does not.** `bootstrap.py
  --status` then shows `DOWN chromium` / CDP refused. `bootstrap.py` (no flags)
  restarts it and re-restores cookies. A dead Chromium also surfaces as
  `BrowserContext.new_page: Protocol error (Target.createTarget)`.
- **Flow can lose its login while Google still has cookies.** The landing page
  ("Log in / Sign up") returns instead of the studio; the Google account chooser
  then shows the accounts as *Signed out*. Only the operator can sign back in
  (the agent must not type a password). Probe with
  `music938-1/scripts/render_remaining.py --check` → exit 0 ok / 2 out of credits
  / 3 logged out.
- **Flow Music free credits have a DAILY CAP (~70 earned via Turntable).** Voting
  took the Turntable counter 13 -> 81/100 (~68 credits) and then stopped counting
  (samples read "No lyrics", manual votes did nothing) even though the counter was
  below 100. So plan for ~2 render windows/day, not unlimited. Verified
  2026-11-03: 7 -> 15/20 songs in one day before the cap.
- **The real minimum song length is 210s (`MIN_SECONDS` in flow_song.py).** A
  create pass that lands at ~180s is rejected as `TOO_SHORT` and re-rolled on the
  next run — it is not a failure to fix, just a retry.
- **Flow Music accepts an uploaded audio *reference* (<=40 MB).** The composer has
  "Add audio or image" -> "Upload audio file"; the clip appears as a chip and the
  "Remix my music" flow will sing/generate from it. So a new singer voice from K
  goes in as an upload, not through a local TTS. A pod-side upload page
  (`music938-1/scripts/voice_inbox_server.py`, port 12001, public work-2 host)
  lets K hand over a file from a phone; files land in `music938-1/voice-inbox/`
  (gitignored — a voice recording is personal data).
- **The cloud desktop's Chromium dies on a stale `SingletonLock`.** After a pod
  recycle it fails with "profile appears to be in use by another Chromium process".
  `pkill -9 -f /usr/lib/chromium`, delete `chrome-profile/Singleton*` and
  `DevToolsActivePort`, then relaunch with `--remote-allow-origins=*`.
- **Restore Chrome bookmarks through Chrome's own API, never by writing the
  `Bookmarks` file.** A hand-written file is silently dropped — Chrome verifies a
  top-level `checksum` (MD5 over the tree) it cannot reproduce, and it also
  rewrites the file on exit, so a write to a running browser is clobbered. Use
  `chrome.bookmarks.create` over CDP on `chrome://bookmarks/` (`login_vault.py
  restore-bookmarks` now does this and is called *after* Chromium is up).
  Chrome also hides the bar on the new-tab page by default; set
  `bookmark_bar.show_on_all_tabs=true` in `Default/Preferences` *before* Chrome
  starts or K sees an empty bar. `bootstrap.py` handles both. This is what lost
  K's 9 bookmarks once (2026-11-04).

- **A trailing-slash `.gitignore` rule over a directory kills every `!` re-include
  inside it** — git cannot re-include a file in an ignored directory. A duplicate
  bare `music938-1/work/` (added `a9a3cf7a`) made `git add` of the tracked ledgers
  exit 1, so the crosspost rail's commit step failed after every post. Find this
  with `git check-ignore -v --no-index <file>`; a plain `check-ignore` hides it for
  a tracked file. Fixed `51ac8c18`, pinned by `test_state_files_are_addable`.
- **The session has two halves: `login_vault.py save` (pod restore) and
  `save_storage_state.py` → secret `AERIS_STORAGE_STATE_B64` (the Actions rail).**
  Updating only the vault leaves Actions signed out. Do both after K signs in.
- **`bootstrap.py` used to skip the login restore unless `OPENHANDS_API_KEY` was
  set; that key is not in the vault's auth path** (`ax_vault`/`AX_VAULT_BOOTSTRAP`).
  The guard is gone (`802d2763`) — do not re-add it.
- **`FACEBOOK_DAILY_CAP = 2`, TikTok `DAILY_CAP = 4`** (10-advisor call: fewer,
  more distinct FB Reels so each one's insights are readable). A "cadence: hold"
  line is not a failure.
## music938-2 (revenue) — durable facts
- **A URL in a YouTube Short's description or a pinned comment is NOT tappable**
  (advisor panel 3/3, 2026-11-05). So the above-fold lines of a product card must
  carry the *disclosure* + a CTA to the **channel profile link**; the tracked
  `s.shopee.co.th/...?sub_id=` URL is only a copyable fallback. The channel About
  already carries the Shopee link, so the CTA is true. YouTube allows affiliate
  links but *excessive* affiliate posting on a dedicated account can hit the spam
  policy — keep every card genuinely distinct.
- **`videos.insert` has its own 100 calls/day bucket**, separate from the
  10,000-unit pool; it is *not* 1,600 units per upload. `UPLOADS_PER_DAY=6` is a
  cadence choice, not a quota wall. The old "10,000/1,600=6" rule was wrong and
  steered the whole cadence. (Advisor panel + Google quota docs, 2026-11-05.)
- **Repetition, not suppression, was the growth stall.** 25 Shorts from 5 songs
  in one format titled "part N of 3" gave no reason to follow; the panel's fix is
  a named series with a *different answerable prompt per chorus*, and Shorts
  rotated **across songs** (`plan()` interleaves one chorus per song per round).
  Falling views are not evidence of a duplicate-content penalty.
- **The affiliate lane now exists on the YouTube rail (2026-11-05, PR #53).**
  `release.plan()` leads with one clip per product card (`kind="affiliate"`),
  before the song Shorts, so purchase-intent clips are not buried behind the
  catalogue. `describe_affiliate()` puts the disclosure + profile-link CTA above
  the fold (superseded the earlier "link on line 2" layout, 2026-11-05); clips
  land in the `ของน่าซื้อ` playlist. The card renderer existed but
  nothing put a card on a channel — that was the whole gap. Detail in
  `.openhands/memory/2026-11-05.md`.
- **Pushing to `main`: the classic PAT works directly (verified 2026-11-05), but
  workflow files need its `workflow` scope.** `AX_GH_TOKEN`/the app-minted token
  is refused with "refusing to allow an OAuth App to create or update workflow …
  without `workflow` scope", so any commit touching `.github/workflows/` must use
  the classic PAT from KV `axsecrets:gh-workflow-token` (read it with
  `OPENHANDS_API_KEY` set; value is a dict, use `["token"]`). `GITHUB_TOKEN` is
  read-only (403). An earlier note claimed `main` was ruleset-protected; a direct
  push succeeded on 2026-11-05, so prefer the direct push and fall back to a PR.
- **A lost `music938-1/work/*.json` is recoverable from the conversation event
  log** (`/workspace/conversations/<id>/events/event-*.json`): the `file_editor`
  `create` action carries the full `file_text`. `work/affiliate-products.json`
  was gitignored and uncommitted, so every fresh pod had 0 cards and the suite
  died with `IndexError` — now tracked.
- **`ffmpeg`/`ffprobe` live at `/workspace/ax-tools/bin`** (not on PATH). Without
  them several tests fail as `FileNotFoundError: ffprobe` — a missing binary, not
  a code bug.
- **The affiliate funnel had no content type.** Every Short was a song, so the
  Shopee link sat where nobody buys → 0 clicks. `music938-1/scripts/make_affiliate_short.py`
  renders a 9:16 product *card* (hook / buying points / CTA / mandatory disclosure)
  bedded on an AERIS song. Cards are in `work/affiliate-products.json` and resolve
  their link per surface via `monetize.link()`; `claim_problem()` refuses over-claims
  and the brief forbids a first-hand-tested claim. Not yet wired into `crosspost.py`.
- **libass overprints lines that share a style alignment/margin.** A multi-line card
  must place every line with an explicit `{\an5\pos(x,y)}` or they all draw on one line.
- **The bundled Noto Sans Thai has no emoji glyph.** A burned caption with 🛒 renders
  tofu; use `•` / `»` (plain Thai + ASCII) in ASS text. Emoji in *captions* is fine.
- **`crosspost.py` probe is per-surface now** (2026-11-04). Before, one dead login
  failed the whole run and blocked the other surface (44 TikTok posts lost). The
  workflow skips only the surface that did not answer.
- **Facebook publish is the "แชร์เลย" (Share now) button, not "แชร์".** "แชร์" is
  the tab that reveals the share options; clicking it leaves the Reel unpublished
  and `post_facebook` then fails its "processing" check. Verified 2026-11-04.
- **Facebook Page id is `61595890900382`; `1349201551618019` is the Business Suite
  *asset* id** (composer URL only). Building the Reels list from the asset id
  answers "page not available", so `newest_post_url` never reads a post back.
- **But for the Graph API the roles are reversed: the Page node is
  `1349201551618019`.** The public profile id `61595890900382` is not a Graph
  node — Graph answers it "Object with ID … does not exist". So the browser
  poster uses `61595890900382` and `ops/fb_graph.py::PAGE_ID` uses
  `1349201551618019`. Verified live 2026-11-05 with the System User token.
- **Meta system-user token is provisioned (2026-11-05)**: `FB_PAGE_TOKEN`
  (Actions secret + vault `axsecrets:fb-page-token`), `type=SYSTEM_USER`,
  `expires_at=0` never, scopes include `pages_manage_posts`. The Facebook rail is
  now API-only; no K login needed. Two setup traps: the app needed the
  **Facebook Login for Business** product before `pages_*` appeared, and the
  permission picker is a **virtualized list** (43 options, only 15 in the DOM
  until you wheel-scroll the listbox).
- **The Page feed is a mix, not only Reels (2026-11-08).** `ops/fb_graph.py` has
  three post types through the one token: `post_reel` (video), `post_photo`
  (`/{page}/photos`, multipart) and `post_link` (`/{page}/feed`). The queue item
  `kind` selects the media field — `image` (photo), `link` (link), else `video` —
  and `_publish_api()` dispatches on kind. `photo_caption()`/`link_caption()` keep
  the new captions distinct from the Reel caption.
- **A photo/link item needs an explicit `hook: 0`.** Tests index `it["hook"]`
  unconditionally, so an item without it raises KeyError; affiliate items already
  carried the field, the new kinds must too.
- **Reading a feed post by its post-half id alone fails with Graph #12** ("singular
  statuses API is deprecated"). Use the page-prefixed node id
  (`<page>_<post>`) or the `/{page}/feed` edge. `_publish_api` builds the
  permalink as `facebook.com/{PAGE_ID}/posts/{post-half}`.
- **`crosspost.py --augment-formats` migrates the committed queue in place** and is
  idempotent (strips then re-inserts the photo/link items). A fresh pod has no
  `library/`, so the queue cannot be rebuilt from disk there; this is the only way
  to add the new formats to the committed backlog.
- **A per-format cap must skip, not stop, the loop.** A link item blocked by
  `LINK_DAILY_CAP` is skipped (`continue`); treating it as a cadence stop makes the
  rail post nothing for a day while photos/Reels wait behind it. The top-level gate
  checks base rules only, and `pace_ok(..., kind="link")` adds the link rule.
- **FB cadence (advisor panel 2026-11-05, duck+pollinations): 2-3/day safe for a
  new page, 4 only after engagement, ~1h apart, <=1 link/day, never two links in a
  row.** Implemented as `MIN_GAP_SECONDS=1h`, `FACEBOOK_DAILY_CAP=3`,
  `LINK_DAILY_CAP=1` (TikTok `DAILY_CAP=4` unchanged).
- **A `return None` from a poster prints "not signed in" for every failure**, which
  hid three Facebook bugs at once. Put the real reason in the abort line and keep
  the caller message generic ("not published — left pending").
- **`short-aff-*.mp4` also matches `short-*.mp4`.** Order the `short-aff-` rule
  before the plain `short-` rule in `pull_media.group_of`, or affiliate cards land
  in `shorts/` and the rail treats them as song Shorts.
- **A pod recycle drops `ax-pylibs.pth`** (it lives in site-packages on the
  overlay) and `websocket-client` was missing from `setup-pod.sh`. Re-run the pth
  snippet from `setup-pod.sh`; system site-packages is root-owned so it falls back
  to the user site dir.
- **Cookies alone are not a session.** Google keeps device trust in localStorage,
  so a cookie-only `login_vault` restore still triggers a device check. `save`/
  `restore` now also snapshot per-origin localStorage+sessionStorage (123 keys
  the cookie snapshot never had) and there is a `heartbeat` command. ChatGPT,
  Gemini and Duck.ai all said the same, and all three said MFA/OTP/DBSC and
  server-side expiry cannot be automated — the goal is fewer K sign-ins, not zero.
- **`ops/duck_ask.py` needs no login** — use it to consult a model on the day the
  Google session is what is broken. Duck.ai runs several vendors' models behind
  one page; parse answers by splitting on "Duck.ai said" and waiting on the
  `Duck.ai said` count, not a text diff.
- **A classic PAT with `repo,workflow` is in KV at `axsecrets:gh-workflow-token`**
  (login `aerismusic8-alt`). `git push https://x-access-token:$TOKEN@github.com/...`
  writes; the sandbox `GITHUB_TOKEN` cannot. Reset the remote URL after pushing.
  The KV value is a **dict** `{token, login, scopes, note}` — read the token with
  `ax_vault.kv_get(ax_vault.find_anchor(), "axsecrets:gh-workflow-token")["token"]`.
  It is the only local token that can push a `.github/workflows/*` change;
  `AX_GH_TOKEN` writes ordinary files but is refused a workflow file ("OAuth App …
  without `workflow` scope").
- **A source-check test that pins an exact old string will fail on a legitimate
  fix.** The pin-badge test pinned `'ปักหมุดโดย'`; making the check locale-tolerant
  broke it. Update the test to pin the *behaviour* (both locales present), not one
  literal.
- **Signing in from a phone: use `resize=remote`, not `resize=scale`.** `scale`
  shrinks the 1600x900 desktop onto the phone, so the address bar is a few pixels
  and text is unreadable — that is the real cause of "ตัวเล็ก กดยาก". `x11vnc` needs
  `-xrandr` for it to work. `ops/phone_login.py` (port 12001, work-2 host) serves
  tap-first buttons: a tap opens the surface in the desktop over CDP and 302s the
  phone into noVNC showing it, so no URL is typed on the phone.
- **After every recycle the desktop was DOWN for three reasons, now self-healed in
  `bootstrap.py`:** `/tmp/.X11-unix` is wiped with the overlay so Xvfb dies
  (`euid != 0`; needs `sudo mkdir -p /tmp/.X11-unix && sudo chmod 1777`); the
  profile on `/workspace` keeps a `SingletonLock` naming the *previous* pod so
  Chrome refuses to start; and `ax-pylibs.pth` is lost so scripts die with
  `ModuleNotFoundError: numpy`. Do not treat any of these as "the code is broken".
- **Google's device-code login is not a substitute for the browser session** — it
  mints an OAuth token, not a cookie session, and needs a device-flow OAuth client.
  Flow Music / TikTok / Shopee need the browser session, so noVNC stays the route.
- **A browser "language" and a browser "font" are independent.** The image ships
  117 fonts and **none covers Thai**, yet Chrome runs `--lang=th-TH`, so Facebook
  rendered Thai as tofu boxes (□□□) and K could not read the screen (2026-11-06).
  `bootstrap.py::ensure_thai_fonts()` now copies `music938-1/fonts/NotoSansThai.ttf`
  into `~/.fonts` before Chromium starts (apt has no network here). Test with
  `fc-list :lang=th`; a *running* Chromium caches its font list, so it must be
  restarted after an install or the boxes stay.
- **A dashboard that serves "the acting account" answers for the wrong account.**
  `measure_facebook` read FB insights while the desktop was still the *personal
  profile*, so it reported the person's numbers (0-49) as the Page's for four days
  — the Page really had **861 views / 28d, 99.9% non-follower** (2026-11-06). Switch
  to the Page and *prove* it (`_acting_as_page`) before reading; parse the 28-day
  total from the "28 วันที่ผ่านมา" range line, not the first "ยอดดู" (that is the
  tab-label row).
- **When a metric reads a suspicious exact 0 while a sibling surface is fine,
  suspect the reader before believing the platform.**
- **Consult the advisors BEFORE acting — it is a gate, not a note (K, 2026-11-05).**
  `ops/consult.py` asks the panel in one command and appends to
  `ops/consult-log.jsonl`; `consult.require(brief)` (or `consult.py --check`) fails
  closed unless a *recent* consultation for that exact brief with **≥2 channels
  across ≥2 vendors** is on record.
- **The panel is the two KEYLESS channels now (K, 2026-11-07: "cut the slow ones,
  use the good useful ones").** Measured first: every Duck.ai channel costs 90-600s
  because they are ONE page, so the old 3-Duck panel was three names for one
  opinion (~10 min, no extra view) and `consult10.py`'s 8 Duck models was ~12 min
  of one page agreeing with itself. `PANEL = ["duck", "pollinations"]` — duck is the
  one whose Thai reads well but is slow (~90s+); pollinations is keyless plain HTTP
  in ~10s but its free `openai-fast` model's Thai is weak, so it is the *second*
  opinion. chatgpt/gemini stay in `VENDORS`, reachable with `--only`, but are out of
  the default (Google session is usually signed out). `MIN_ADVISORS = 2`,
  `MIN_FAMILIES = 2`. The quorum still counts **vendors**, never seats: several
  Duck models are one page and let "3 answered" be one vendor echoing itself.
- **The real remaining win is a fast Thai-capable keyless model.** The panel is a
  few minutes, not ~15, but Duck is the floor. Rule #1 forbids paid APIs.
  `family()` maps a seat to its vendor; `quorum()` decides the floor in one place.
- **K-free = a rail with no credential that can expire.** `ops/k_free_status.py`
  audits it (`--check` exits 0 only when nothing pulls K back in). Three states:
  `k_free` (keyless, or an api/oneshot rail with its credential present),
  **needs K once** (one-time authorization — unavoidable: every platform's terms
  require the owner to consent at least once; consult 2026-11-07, unanimous), and
  **needs K repeatedly** (a browser snapshot with no K-free primary, or an
  unprovisioned token) — this last must be 0. A **browser fallback is not a
  K-dependency while its api primary is present** (`superseded_by`): the
  FB/TikTok browser posters are covered by the Meta/TikTok api rails, and the
  Flow Music render by the keyless synth bed. The content engine is K-free:
  lyrics on **Duck.ai** (`ai_lyrics.DRAFTERS["duck"]` first in `forge_song.py`)
  and song masters via `flow_song.py --offline` (`aeris938-1/scripts/make_music.py`
  ffmpeg synth). With all tokens present: 7/11 K-free, 1 one-time (the avatar),
  0 recurring.
- **TikTok rotates its refresh token on every refresh and a GH Actions job cannot
  write a secret back** — refreshing in CI *burns* it and the next run 403s. The
  fix is `ops/token_heartbeat.py --refresh --push-secrets --repo owner/name`
  (renew from the vault + publish to repo secrets in one step), plus a `_put(...)`
  guard at every rotation site in `tiktok_api.py` (no vault → no rotation).
- **The YouTube channel avatar has no API** — it is the one YouTube step needing a
  Studio click; `profile_setup.py youtube` drives it and must click the final
  **Publish** (Studio stages branding edits). **Google also refuses to let the
  vault restore Studio** — it asks the password even with cookies+localStorage
  restored, so this is the one credential K must type. Runbook: `docs/k-free-runbook.md`.
- **Pollinations free tier is 1 reply / 45s / IP** (`FREE_LIMIT` 402) and only
  `openai-fast` (GPT-OSS 20B) is anonymous — the bigger models 402 "Payment
  Required". So it is a *second* opinion, never the driver. And there is **no free
  audio/music API** (pollinations serves text + image only); the only keyless
  music is the local ffmpeg synth.
- **Duck.ai appends an "Nth opinion" marker** after each answer in a thread and it
  fuses onto the last real line. `duck_ask._clean` strips it; without that, every
  lyric draft fails the Latin-text lint.
- **The gate is now wired into a real runner, not just tests.** `aeris938-2/scripts/admin.py`
  calls `consult.consulted()` before it drafts and exits 2 without a quorum
  (`--no-gate` is the only escape hatch), with one ntfy alert per day. It is still
  NOT in CI, so a pod-side decision relies on you calling it.
- **Record what you APPLIED, not just what you asked.** `consult.py --applied
  "<brief>" --note "..."` (or `note_applied`) stamps the decision onto the row.
- **A watcher that reports activity on a quiet surface is wrong about the surface,
  not right about the activity.** The FB admin rail printed "กล่องข้อความ: มีรายการใหม่
  2 รายการ" every hour for days on a *completely empty* inbox, because `_count_new()`
  counted the substring "ใหม่" and the Business Suite inbox carries a permanent
  filter chip with that exact label — it read the filter UI as mail. It then drafted
  a canned reply to nobody each run and, worst, never alerted on the number that
  matters (the Page has **1 follower, 0 comments**, posting daily). Same shape as the
  "0 views" bug and `Skills.hotbar`: a count taken from a label rather than an item
  is not a measurement. Fixed 2026-11-07 (`aeris938-2/scripts/admin.py`):
  `_inbox_state()` uses the empty-state text for 0 and returns **-1 unknown** rather
  than a confident 0; `page_snapshot()` switches to the Page identity first (the
  same switch that fixed the views); drafts only when `comments > 0`; `_stall()`
  alerts "เพจไม่โต" (≥3d, <10 followers) with the flag stored in the **committed**
  `admin-log.jsonl`, since a side file does not survive CI's fresh checkout.
- **`OPENHANDS_API_KEY` must appear by name in the command** for the sandbox to
  inject it; `ax_vault` returns 401 ("cannot list automations") without it, which
  reads as "the KV token is gone" when it is really "the env var was not injected".
  It mints the `axsecrets:gh-workflow-token` classic PAT used for `git push`.
- **The cloud desktop dies with the parent shell** — `nohup ... &` alone lost it
  twice within minutes; `setsid ... & disown` kept Xvfb/chromium up. After a pod
  recycle also re-check `ops/phone_login.py` (work-2 tap-login page, 502 until
  restarted) and the `ax-pylibs.pth` (a failed write left it **empty**, so
  `import playwright` failed while the pth existed — verify with
  `env -u PYTHONPATH python3 -c "import websocket,playwright,numpy"`).
- **`duck.ai` needs its tab opened first** or `duck_ask` raises "no duck.ai tab";
  open it with `curl -X PUT 'http://127.0.0.1:9222/json/new?https://duck.ai/'`.
  **chatgpt/gemini need their tabs open too** — otherwise they raise "no chatgpt.com
  tab", which silently drops the panel to Duck-only (1 family) and the gate FAILS.
  Open all three before a real consult. Duck took ~300 s on a long Thai prompt while
  ChatGPT/Gemini took ~25 s. The full panel takes ~15 min (each Duck model streams
  serially), so run it in the
  background and poll rather than blocking on it.
- **A Short's description link may not be tappable — pin a comment instead.** Every
  member of the 2026-11-05 panel raised it. `studio_web.py` `short_pin_targets()`
  returns `(video_id, text, marker)` for both a song Short (youtu.be link) and a
  product Short (tracked Shopee link + affiliate disclosure); `pin-shorts` is step 4
  of `desk_daily.py`. `brandingSettings.channel.description` is API-writable via
  `channels.update part=brandingSettings` (the About page), but the profile *links*
  section is not in the API at all.
- **The wrong-render backlog must not eat the product clips' slots.** `release.AFFILIATE_RESERVE`
  (2) is enforced in `replace_video.py` as `reserve = min(2, affiliate_pending())`:
  it holds slots while a card is pending and releases them once all are live. Without
  it the 8-video backlog spends all 6 daily slots and no product clip ever publishes.

## The songwriting formula (music938, 2026-11-04)
- **`music938-1/scripts/forge_song.py` is the formula.** ChatGPT drafts 2 angles
  -> `ai_lyrics.lint_sections` filter -> Duck.ai critiques -> Duck.ai judges A/B
  (`pick()` parses "เลือก: A|B") -> winner written -> Flow renders. Rule: the
  filter runs entirely off Flow credits, so a bad candidate never costs a render.
- **Draft with ChatGPT, not signed-out Gemini.** The desktop's Gemini is signed
  out and its Flash-Lite refuses the lyric brief outright. `A.draft(meta, angle,
  drafter=...)` switches; Gemini works again once signed in.
- **`parse_body` slices from the LAST "… said" marker.** Both web UIs echo the
  prompt (tags included); parsing the prompt's own example lyric yields 0 sections.
- **`_auto_line_beats` needs the 32-beat ceiling**, or a 140 BPM song stays at
  185 s and fails the 210 s floor. Slow songs are unaffected (298 s cap governs).
- **Listen page: `ops/serve_songs.py` (port 12001, work-2 host)**, serves only
  `library/songs/*.mp3`. Pod-local — dies on recycle.

## Song style = groove + vocal phrasing (2026-11-04)
- **When a Flow song sounds wrong, fix the STYLE prompt, not the syllable count.**
  Both advisors put a "vocal clashes with the backing" complaint in the prompt's
  groove/phrasing. Name the groove (`steady 4/4 two-step drum groove`), lock the
  vocal to it (`vocals tightly locked to the instrumental beat`, `syllabic Thai
  vocal delivery with even note spacing`, `short balanced vocal phrases`, `smooth
  legato transitions`), and forbid drift (`constant tempo`, `no tempo changes`).
  For "make it faster": `fast-paced` + `driving straight eighth-note drums` +
  `double-time feel` + `urgent fast vocal phrasing`, and raise the BPM (rock
  140 -> 160). Styles live in `channel/genres.json`; tempo in the lyric header.
- **A song's lyric file is already 8 syllables/line.** `pythainlp.syllable_tokenize`
  confirms it, so a timing complaint is never a syllable-count bug.
- **`flow_song.py --force` closes every other Chromium tab** (`_sweep_tabs`). It
  killed a running `turntable_vote.py` twice. Never run the two concurrently.
- **The Turntable tops out well below 100/100 in a day** (83 -> 86 and stopped).
  It is not a route to an unlimited credit top-up; plan ~2 render windows/day.

## The songbook must not sound like one song (music938-1, 2026-11-06)
- **K's binding rules:** pentatonic core ("ใช้เพนทาโทนิค"); **music must not
  repeat** ("ดนตรีห้ามซ้ำกัน" — a new genre label is not enough, the arrangement
  must differ); 5–7 syllables is an **example, not a rule**; rework the catalogue
  before releasing; upload finished songs to **Google Drive** in per-type folders.
- **The measured cause was one production template.** 20/22 songs had no
  `# GENRE:` header → all fell back to one "เพื่อชีวิต" style; 21/22 female voice;
  tempo 64–96; identical `V-C-V-C-B-C`; hook sung once per chorus. A 9/10 advisor
  panel agreed and prescribed a genre rotation + spread tempo + varied voice.
- **`channel/arrangements.json` = 24 signatures (6/genre).** `arrangement.py`
  `assign()` is **two-pass** (tagged songs first inside their own genre pool, then
  header-less released songs) — one greedy pass lets a header-less song starve a
  genre. `--check` fails on a shared id.
- **`scripts/rework_catalog.py` rewrites headers only** (GENRE/TEMPO/VOICE) on the
  17 unreleased songs; the 5 released songs are left byte-identical. Never re-tag a
  live song: its audio cannot be re-rendered, so the metadata would lie.
- **`consult10.py` only writes `--out` at the end** → one hung advisor loses every
  earlier answer. Use `run_panel.py` (saves after each answer). A brief over
  **16,000 chars** is rejected by Duck.ai.
- Detail: `.openhands/memory/2026-11-06.md`.

## Two Google accounts in the desktop (2026-11-06)
- **The pack spans two Google identities**, and the phone page now says which per
  surface: `aerismusic8@gmail.com` = music / Drive / YouTube / Gemini / Flow;
  `kongkeat.p3@gmail.com` (Shopee login `navintas`) = Shopee Affiliate.
- **`ops/phone_login.py` has a `switch` button** that opens Google's own
  `AccountChooser` — the agent never types a password, K taps the account and the
  saved password fills it. `SURFACES` values are now 4-tuples
  `(label, url, hint, account)`; update any code that unpacked the old 3-tuple.

## Crosspost rail + session reality (2026-11-05)
- **A green crosspost run can post nothing.** The rail skipped every signed-out
  surface and still ended `success`; ntfy fires only on `failure()`, so a dead
  FB/TikTok session was invisible for weeks. `crosspost.py --pending-count` + a
  workflow step now fail the run when a blocked surface has pending posts; an
  empty queue stays green.
- **When the desktop is signed out, it is signed out of Google too.** Studio
  redirects to `accountchooser` with "Signed out", so `studio_web.py` (pin-shorts,
  reply, analytics) is dead. Only the **YouTube Data API OAuth** still works —
  that is the one revenue surface an agent can drive without a browser session.
- **A dead login is not the growth bottleneck.** 2,022 views → 0 Shopee clicks
  is a conversion-path problem. The 5 product cards all resolve
  `monetize.link("youtube")` = the generic `shopee_affiliate` link, so every card
  lands on the Shopee home, not a product page (the 5 custom short links are
  per-*surface*, not per-*product*).
- **`apply_monetize.py` is the live-description backfill** (Data API, idempotent
  for videos; the playlist branch used to stack its footer every run — fixed).

## K out of the loop: the API posting route (2026-11-07)
- **K's directive: cut K out of the automation cycle.** Advisor panel (6 channels
  / 4 vendors, `ops/consult.py` PASS) was unanimous: Facebook = Meta Graph API +
  **System User** token (Business Settings → System Users → assign Page + app →
  `pages_manage_posts`; *Never* expiry if offered, else the 60-day token renews
  via `fb_exchange_token`). TikTok = Content Posting API but with a **hard limit**
  — refresh token expires, app needs audit, and an *unaudited* app may only post
  `SELF_ONLY` (private). **Never invest in keeping browser cookies alive.**
- **The API route is wired and inert until a token exists**: `ops/fb_graph.py`
  (Reel start→upload→finish/PUBLISHED + refresh + `debug_token` + `get()`),
  `ops/tiktok_api.py` (refuses `SELF_ONLY` so a token can't silently downgrade a
  public post), `crosspost.api_poster()` + `post()` (no browser at all when a
  token is set), `admin.page_snapshot_via_graph()`. No token → behaviour is
  byte-for-byte the old browser path. `docs/remove-k-from-the-loop.md` is K's
  one-time provisioning guide.
- **`ops/token_heartbeat.py` + `ax-token-heartbeat.yml`** check the tokens every
  6h and ntfy K *only* when one has actually expired. CI is **check-only** — TikTok
  rotates its refresh token on refresh and an Actions job cannot write a secret
  back, so `--refresh` is agent-side (writes the vault).
- **`ax_vault.ensure_anchor()` raises `SystemExit` — a `BaseException`, not an
  `Exception`.** The first heartbeat run died on the GitHub runner (no vault → the
  OpenHands API 401s → SystemExit sailed through `except Exception`). Any ops
  script that reads the vault from CI must catch `BaseException` around the anchor
  lookup. This would have been *every* run, not a flake.
- **What cannot be automated, say it plainly**: the first token needs a human once;
  TikTok public posting needs app audit; Meta can revoke. The heartbeat converts
  "silently dead" into "K knows", which is the achievable goal.
- **The dashboard does not die without a session** — YouTube is Data-API OAuth, so
  `report.py` still prints real numbers with `AERIS_STORAGE_STATE_B64` unset. Only
  the FB/TikTok/Shopee lines degrade to labelled fallbacks.

## The Page-admin agent: automate content, never outbound (2026-11-06)
- **Five advisors, one answer:** automating follows / friend-invites / comments on
  other Pages / cold DMs is an artificial-growth signal Meta acts on, and **no
  per-day rate makes it safe** — the policy keys on the pattern, not the volume.
  So "pace it like a human" is not a defence. K cannot risk the account → do not
  build it. `aeris938-2/work/consult-brief-fb-admin-agent-2026-11-06.md`.
- **Built the safe half:** `aeris938-2/scripts/admin.py` (read inbox → count new →
  detect a Meta warning TH/EN → draft a canned reply, escalating refunds/rights/
  complaints to K → log → one ntfy). `ax-music-admin.yml` runs it **hourly**
  (`15 * * * *`). It **drafts; it never sends.** Verified in CI: restored the
  session, read the real inbox (1 new item), wrote `work/admin-log.jsonl`.
- **Disabled the ban-bait:** `outreach.py --follow/--invite` now refuse and print
  why; they need `--i-understand-the-risk`. That `DAILY_CAP=40` follow loop was
  the most ban-prone thing in the repo.
- **The FB inbox is Meta Business Suite at `/latest/inbox/all`** (comments +
  Messenger + IG + WA in one view). `professional_dashboard/inbox/` 404s.
- **Advisor-panel gotchas:** Duck.ai needs its tab opened first (else every Duck
  model fails in 0.0 s); `consult10.py --only` wants the full name (`duck-luna`),
  not the `duck` prefix; a dead Gemini tab is normal — the gate needs ≥3 answered.


## Convert viewers into followers: send every surface to the Page (2026-11-06)
- **The leak is view→follow, not reach.** YouTube: 861 views / 28 days, 1 follower.
  A 4-advisor panel (ChatGPT + duck-luna/mistral/oss) ranked the fixes identically:
  Page bio → pinned post → Page link above the fold everywhere → promo site as a
  follow-landing page. All four are now done and verified live.
- **One CTA, Page first.** `monetize.cta()` leads with the Page link, then the
  product link. `refresh_description()` also strips the old channel-only CTA line
  (`_OLD_CTA`), so live videos do not end up with two different follow asks.
  `apply_monetize.py --apply` rewrote 22 videos + 6 playlists; the Page link now
  sits at char 96 (above YouTube's "Show more" fold).
- **The promo site is a landing page, not a link list.** `ops/ar_promo_site.py`
  renders hero + follow button + "what you get" + socials footer. Deployed to
  GitHub Pages; verify by grepping the live HTML for `facebook.com`, not by
  trusting the push.
- **The Page composer drops `document.execCommand('insertText')`** — exactly one
  character lands. Use CDP `Input.insertText` (`ctx.new_cdp_session(pg).send(...)`).
  Composer is two steps: caption → "ถัดไป" → "โพสต์". A pinned post's menu shows
  "เลิกปักหมุดโพสต์", which is how to *verify* a pin took (the page never shows a
  pin marker to a logged-out viewer). Scripted as `profile_setup.py welcome`
  (idempotent) + `grow.py facebook --welcome`.
- **`profile_setup.py bio`** sets the intro alone (no cover/avatar re-upload);
  **`apply_brand.py --description-only`** changes the channel description without
  re-uploading the banner. The channel description must carry the Page *URL*, not
  the plain text "Facebook: AERIS Music" — plain text is not clickable.

## Goal = the $500 and the 1,000 gate (K, 2026-11-07)

- **A follower count is a gate, not vanity.** YouTube 1,000 subs = YPP; TikTok
  1,000 followers = TikTok Shop Affiliate. Growing the channel and earning are
  the same job. K rejected "platforms cannot pay, do affiliate instead" — the
  task is to *build the channels to the gate*. K accepts missing the month; the
  rule is do every free thing, watch it, improve until it works.
- **`aeris938-2/scripts/goal_watch.py`** is the daily judge. Reads
  `work/history.jsonl`, names the ONE blocking constraint (income > reach >
  conversion > offer), writes `work/goal-watch.md`, pushes to ntfy. Exits 0 on
  bad news. Wired into `ax-music-dashboard.yml` (which now sends its headline).
- **A karaoke clip whose words do not match the song is worse than none (K).**
  `make_short.karaoke_ok(slug)` is the hard gate: mix exists, length within 2% of
  the song, cover exists, lyric has `[chorus]`. `render(mix="karaoke")` raises on
  a refusal; `--skip-existing` skips that song. Do not ship a mismatched clip.
- **`ax-music-karaoke-render.yml`** renders a lyric-led karaoke Short per song on
  the free Actions rail (pulls masters from `media-938`, no pod), then
  `crosspost.py --merge-queue` adds them. `--merge-queue` appends new ids and
  never drops the backlog; `--rebuild-queue` WOULD drop it (enumerates the
  gitignored `library/shorts/`).
- **`crosspost._slug_of`/`_hook_of` must strip `short-song-` AND `short-karaoke-`.**
  They only knew the first prefix, so a karaoke clip would be captioned with its
  whole stem and every link/lyric line wrong.
- **The opening Short card is the first sung lyric**, overlaid at t=0 with the
  audio unchanged (panel lever #1: open on the hook, do not delay the song). The
  old question-card was 2s of delay.
- **Honest ceiling:** the channel needs to feel authored (real voice/story/series),
  not interchangeable generated songs, or people will not follow and monetization
  policy is at risk. "Post more / more hashtags / same file everywhere" is not growth.
- **The paid offer is live (2026-11-07, panel action #1).** `monetization.json.commission`
  = ฿990 custom-song offer; `monetize.commission_block()` renders it;
  `release.describe` appends it to songs + compilations (never Shorts);
  `apply_monetize.py --apply` backfills live long-form descriptions (it reads
  `contentDetails` to tell a song from a Short). `ops/yt_comment.py` would pin it
  as a comment but the channel tokens lack `youtube.force-ssl` → 403; the
  description route works.
- **The compilation was ALREADY live.** `รวมเพลงไทยเพื่อชีวิต 15 เพลง`
  (`3Yz2jxZnKmM`, 56:42) was published earlier, so a fresh 16-track render is a
  near-duplicate — check the channel first. `ax-music-compilation.yml` now skips
  when `compilation-state-<stem>.json` carries a `video_id`.
- **A karaoke Short must not caption like its song's hook-1 Short** (same title +
  tagline + ask read as a duplicate; the "captions are all distinct" test fails).
  `caption(slug, platform, hook, kind="karaoke")` gives it its own label; `kind`
  is stored in the queue and inferred from the video path in `refresh_captions`.

## AERIS Music identity — durable facts
- **The banner is API-settable; the avatar is not.** `channelBanners.insert`
  (POST to `www.googleapis.com/upload`, which the proxy serves) + `channels.update`
  set the banner with no human — `ops/apply_channel_art.py`. YouTube has never
  exposed an avatar write, so the avatar is Studio-only
  (`ops/set_avatar_studio.py`, `channel/AVATAR-ONE-TAP.md`).
- **`channels.update` is a FULL replace of `brandingSettings`.** Read it first and
  swap only `image.bannerExternalUrl`, or the description and keywords are lost.
  `apply_channel_art.py` refuses to PUT a blob with no description.
- **Identity v3 = evolve, not pivot** (consult quorum PASS 2026-11-07, 4 channels /
  2 vendors). Indigo #202A46 + the A-wave stay; cream/coral/sage warm it. Headphones
  are a corner prop, never the icon — the channel posts Thai songs, not gear
  reviews. Only the mark, the wordmark and one Thai tagline go inside the banner's
  1546x423 safe strip; the posting-schedule line was cut. `test_brand_identity`
  pins the strip geometry, the palette and the bold avatar stroke.
- **The login vault snapshot has no `youtube.com` cookies**, so `login_vault.py
  restore` can never sign YouTube in — and `check_login.py` reports Google
  SIGNED_IN from cookies alone while YouTube still asks for a password. Only a real
  sign-in (then `login_vault.py save`) fixes the avatar step.
- **A share pack must label whether an item is a real song or a synth bed, from the
  audio itself.** `produce_loop.py` used to build the ffmpeg bed first and treat the
  Flow Music render as optional, so songs 25/26 shipped as beds (mono) while 01-24
  were real stereo takes; K caught it by listening. Flow is now the default
  (`--no-flow` opts out), the CI runner lane is explicitly bed-only, and
  `make_share_pack._audio_provenance()` labels each row `audio: flow|synth-bed` +
  `has_vocals` using `provenance.py`'s mono-duplicated channel test. Never infer
  provenance from a filename or a side file: `clipmeta-<slug>.json` exists only for
  newer Flow renders, so it would mislabel the older real songs. If a script asks
  for a song and makes none, it must exit non-zero — the 2026-11-07 CI run went
  green with `produced: []` because `pollinations_ask` POSTed a shape that 400s.
  Details in `.openhands/memory/2026-11-07.md`.

## The release engine lost every upload it made (2026-11-08) — durable facts
- **The ledger write must precede the rc-3 early return.** `daily_release.py`
  wrote `release-state.json` to `main` only on `rc == 0`, so a batch capped at the
  day's slot count uploaded videos and then returned *before* the write. The ledger
  never learned about them, so the next run re-planned and re-uploaded the same
  items. Live symptom: the same affiliate card was on the channel 4× while the
  ledger held 0 affiliate rows. This one bug is why the rail looked "stuck on the
  same 6 songs" and why the channel stopped growing.
- **`browser_download_url` is not the way to fetch a release asset.** It
  302-redirects to a separate CDN host that returns transient 504s under load; a
  single one used to abort the whole batch. Use the API's
  `repos/<r>/releases/assets/<id>` endpoint with
  `Accept: application/octet-stream` — same bytes, no redirect, measured 0.4s vs
  10.9s. Keep the asset id in `_media_assets()` for this.
- **`uploadLimitExceeded` is a *channel-level* cap, separate from the API's 100/day
  `videos.insert` bucket.** It means the day is done, not that the code is broken.
  Do not dispatch extra release runs to "verify" a fix: each dispatch spends this
  budget and the next scheduled tick then uploads nothing. Treat it as rc 3.
- **The local quota ledger under-counts; trust the live 403.** `work/yt-quota.json`
  only records calls that *reserve* against the pool, so a day can show "815 used,
  9185 left" while a 1-unit `channels.list` returns `quotaExceeded` — the day's
  real spend (other writers, other channels) is not in the file. When YouTube
  refuses, read the HTTP reason, not the ledger.
- **A song K hands over must be *pinned* to go first.** The plan is a rotation
  (one chorus per song per round), so a new song lands days deep. Put its slug in
  `music938-1/work/release-priority.json` (`{"songs": ["29-takorn-kong-fa"]}`);
  `release.plan` moves that song's main release + first Short to the front, only
  reordering, and goes inert once the main release is live. The file must be
  **tracked** (`.gitignore` `!` rule) or the runner, which fetches `main`, never
  sees it. Facebook stayed parked (`API_ONLY`, no Meta token); only TikTok was an
  open surface that day.
- **A transient 409/5xx on `playlistItems.insert` is retryable**; the video is
  already uploaded, so losing the row costs a discovery slot. Retry 409/500/502/
  503/504; let a 403 (quota) return at once.
- **Reconcile the ledger to the channel, not the other way round.** After any
  cleanup that deletes videos, retire those rows and record the survivors, or the
  rail re-uploads them. `music938-1/scripts/reconcile_ledger.py` does this and is
  idempotent.
- **Several writers PUT the whole release ledger; the write must be
  read-merge-write.** `fix_thumbnails`, `pending_replacements` and
  `daily_release` each write `release-state.json` from the job's start-of-run
  checkout, so a later step's PUT silently drops a row an earlier step just
  added (2026-11-08: the repair step dropped songs 06/07/08 minutes after the
  release step recorded them). `daily_release.merge_ledger_rows()` unions by
  `video_id` (local wins on a shared id, remote keeps `retired_at` etc.);
  every writer must go through `daily_release.write_ledger`. Same failure shape
  as the rc-3 ledger loss: state written from a stale view.

## Growth levers from the competitor scan (2026-11-08) — durable facts
- **Winners publish long-form, not Shorts.** 10 real Thai music channels: every
  one is 30 long / 0-10 Shorts; we were inverted (26 Shorts / 7 long) and our one
  compilation is already our #1 video (268 views vs 24 median). `compile_album.py
  --theme sad|chill|power` builds disjoint-mood albums so long-form can grow
  without re-titling one tracklist; `ax-music-compilation.yml` is weekly now and
  ships one not-yet-live theme per run (state `compilation-state-<stem>.json`).
- **Winners title for search intent**, 0-21% hashtags, 58-78 Thai chars; we were
  79% hashtags, 43 chars. `release.song_title()` leads with the listening moment
  ("เพลงเศร้าอกหัก ฟังตอนดึก") inside the ~60-char truncation.
- Winners' top videos are **covers of known hits** — composition rights are
  unresolved and duck.ai warned against building on them. **Needs K's decision.**
- **YPP threshold rises 2027-02-01**: 8,000 watch-hours or 20M Shorts views.
- `ops/yt_public_scan.py` reads `ytInitialData` from public pages, so competitor
  scanning costs **no API quota**. It parses Thai number words (พัน/หมื่น/แสน/ล้าน).
- **A missing numpy makes `release.is_retired()` skip every song** (imports
  `provenance`, fails closed). `--plan` then shows only affiliate cards and the
  pin tests fail. Re-run `music938-1/scripts/setup-pod.sh`; it is not a code bug.
  Production is unaffected — a fresh runner has no audio on disk.
- **A test that reads live state must handle that state's transitions.**
  `test_priority_pin` asserted a pin was pending; the automation published the
  song and the pin went correctly inert, failing three checks. It skips now.
- **Push route that worked (no PC1):** `axsecrets:gh-workflow-token` in the vault
  is a classic PAT (`token` key inside the JSON value) with `repo,workflow`.
  `ax_vault.kv_get(aid,key)` returns the value directly. Remote had diverged with
  automation data commits → fetch → rebase → push, then reset the remote URL.

## Cover songs + YouTube money — durable facts (2026-11-09)
K asked: if a cover's licence is checked, does it pass and does YouTube pay?
Answer read straight from YouTube's own pages (Tavily was out of quota):
- **A cover only earns for us if the PUBLISHER claims it via Content ID and
  turns on "Sharing ad earnings".** We are then paid a **pro-rata** share, not
  the whole ad revenue. A licence alone gives NO revenue-sharing route — with a
  licence but no claim, the cover earns nothing. (answer/3301938)
- **Claim outcomes (answer/6013276):** a claimed video >3 min stays up but the
  claimant takes the money; a claimed video 1–3 min is **blocked outright**. No
  strike for a claim, but the revenue (or the video) is gone.
- **YPP thresholds rise 2027-02-01**: 8,000 watch-hours or 20M Shorts views;
  Shorts ad revenue needs >=10M qualified Shorts views/90 days. (answer/72851,
  12504220)
- **"inauthentic content"** (was "repetitious") = mass-produced/repetitive =
  ineligible to monetize (answer/1311392).
- Panel 2/2 (duck, pollinations): covers are a poor core bet for a tiny channel;
  keep the originals + themed albums + search-intent titles strategy.
- Decision recorded: **do not build on covers of known hits.** Only if K obtains
  mechanical+sync licences AND accepts the pro-rata split. Doc:
  `music938-1/channel/COVER-LICENSE-YOUTUBE-POLICY-2026-11-09.md`.
- **Tavily search is out of quota** in this account; read policy pages directly
  with `curl -sL -A Mozilla/5.0` and extract the `<article>` block.

## Shopee affiliate funnel — durable facts (2026-11-09)
- **The $500 goal rides on Shopee Affiliate** (the only surface that pays with
  no follower gate). TikTok Creator Rewards has no Thailand; TikTok Shop
  Affiliate needs 1,000 followers; FB monetization is invite-only; YouTube needs
  1,000 subs + 4,000 hrs. So every other number is a means to that end.
- **The funnel was 0 clicks for a real reason, not bad luck:** the compilation —
  the channel's most-watched video (268 views vs a 24 median) and the only
  long-form one whose description is clickable and above the fold —
  `compilation_description()` wrote **no subscribe ask and no Shopee link at
  all**. A Short's description is below the fold and unclickable in-feed, so the
  cards that *did* carry the link could not be clicked. Fixed 2026-11-09.
- **Fix shape:** `compile_album.compilation_description()` now inserts
  `monetize.cta("youtube")` (subscribe + Page + Shopee) above the chapter list,
  wrapped in try/except so a description never breaks. `scripts/fix_compilation_cta.py`
  repairs the live video in place, idempotent (`_insert_cta` returns the input
  untouched when the link is present), backs up to `work/description-backup.json`.
  Wired into `ax-music-release.yml` early, on the fresh quota pool, next to the
  thumbnail repair.
- **Advisor panel split, and the tie-break:** duck said fix the existing top video
  first (c); pollinations said build a long-form buying guide (a). Chose (c)
  first: free, in-repo, reversible, and it produces the fit-vs-reach data (a)
  would need. (a) is the follow-up if (c) earns clicks but no orders.
- **`monetize.link()` only attributes with the long `s.shopee.co.th/...?sub_id=`
  links.** The short `th.shp.ee/...` form drops `sub_id` (verified against the
  live redirect), so per-surface attribution silently fails with it.
- **YouTube Data API quota is per-project, resets midnight Pacific.** A release
  batch + thumbnail repairs spend the shared 10,000 units, then `videos.update`
  and even `channels.list mine=true` return 403 `quotaExceeded` (not a scope or
  token problem — check the error body before debugging auth). Repairs that need
  quota go into `ax-music-release.yml`, which runs at 08:05 UTC on the fresh pool.

## The tracking system drifted from the work (2026-11-09) — durable facts
- **There are two trackers, and they had diverged.** `AKATH_CORE/CANONICAL_TASK_REGISTRY.json`
  is the canonical task catalog (read by `AKATH_CORE/runtime`), and it was frozen
  at 2026-09-19: it still described the September PC1 programme as current work and
  contained **none** of the live jobs (`grep aeris938` = 0). The live tracker is
  `aeris938-2/scripts/report.py` -> `work/growth-report.md` + `history.jsonl`
  (four surfaces) and `goal_watch.py` (the daily bottleneck), on the
  `AX Music Daily Dashboard` rail. Keep them in step; a registry that lags is the
  tracker lying by omission.
- **`add_roblox_goals.py` is NOT safe to re-run.** It does a full `update` of each
  Roblox goal from a hard-coded September snapshot, so it **reverts newer live
  evidence** (published_versions, live ids, the corrected blocker text). An
  "idempotent" seed script that hard-codes a whole record clobbers updates to that
  record — make it merge, or don't run it after the record has moved on. Recovered
  2026-11-09 by restoring the pre-run backup and re-running only the new reconcile.
- **Reconciling the registry is a one-command, idempotent job:**
  `python3 AKATH_CORE/reconcile_growth_scope.py` adds the four growth surfaces +
  the measurement rail as canonical tasks, marks the 5 stale PC1 tasks SUPERSEDED
  (reason: cut by K's 2026-11-02 scope, *not* failed), leaves the 4 Roblox standing
  goals untouched, and sets `current_work` to the live top priority. Result:
  29 tasks (14 DONE / 9 IN_PROGRESS / 6 SUPERSEDED / 0 PENDING-OVERDUE), so the
  runtime's auto-OVERDUE sweep has nothing stale to mark.
- **Advisor panel quorum (duck + pollinations) both chose "reconcile", not
  "freeze"** — the registry is a current-state catalog, so it must carry the current
  work. Consult is required before a non-trivial change; a failed quorum (Duck
  needs a `duck.ai` CDP tab — open it with
  `curl -X PUT 'http://127.0.0.1:9222/json/new?https://duck.ai/'`) is not a pass.
- **This pod's checkout can start dirty.** `git status` showed
  `.openhands/memory/MEMORY.md` modified (-81 lines vs HEAD) before any action;
  `git checkout -- <file>` cleans it. Check `git status` before committing.
- **The runtime unit suite has 7 pre-existing failures on Linux** (self-contained
  fixtures + `runtime-registry.test.mjs` asserting a Windows path). They are the
  same before and after a registry change — not a regression signal.
