# MEMORY — index
**Capped 6 KB** (`ops/memory_guard.py`): rules/pointers only, detail in
`MEMORY-ARCHIVE.md` + daily logs. **Read `.openhands/CHARTER.md` first.**

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
100% free: no paid API, subscription or credits. Free routes only — login-only web
apps (K's Chromium), open APIs, self-hosted tooling. **AR never types a password.**
**AUDIO FIRST**; delete the duplicate/worthless, never archive it; K reviews a
channel's first work; never rename a channel without K's approval.

## 🧭 THE COMPASS — the one direction for NEW work (K 2026-11-20)
K: "แนวเพลงสร้างคลิป ไม่มี เข็มทิศหายแบบนี้ก็หลงทางสิ". `ops/compass.py` is the
single answer to *which lane may produce what, at which standard, into which
folder*. **Read it before touching a clip lane; add a row before adding a rail.**
Row shape in archive; it **fails closed** (`assert_lane`, `may_render`).
- **`compass.songs(lane)` is the only way a lane lists songs**;
  `compass.is_publishable(slug)` is the single-slug form; `--check` must be
  clean. Globbing `song-*.mp3` rendered 18 of 32 masters in a parked genre.
- **A bed is not a song: the compass filters BOTH**; a slug on argv must call
  `compass.require_publishable`. List and single-slug forms must never disagree.
- **`pull_media` never overwrites a differing local file** (the release lags an
  upload); report it, `--force`.
- **The product is a SONG clip, not a narrated one** (`narration` only where K
  asked by name: `trivia`; `story` is a **tool**). Old posted clips untouched.
- **`mv` has a rail** (`ax-music-mv`: 4K → media-938; publish stays in
  `release.py`); `film` still none. Karaoke rail deleted (K 2026-11-21).

## Genre = FUN ONLY — **five main lanes** (K 2026-11-21)
**Active: pop / rock / rap / hiphop / alternative** (`main_genres` in
`channel/genres.json`). Everything else PARKED = ห้ามอัพ (edm, synthpop, citypop,
เพื่อชีวิต …). **ทำทั้งช้าและเร็ว, ทุกเพลงต้องมีท่อนฮุกติดหู.**
**All 20 `lyrics-original/` songs are เพื่อชีวิต — never publish them.**
`genres.publishable()` fails closed at **every** publish path; `--list-songs`
stdout must stay pure (a log line piped to `shuf` killed the lane once).

## Roles and method (K 2026-10-31)
**K = final authority.** **AR = me**: I administer all of K's work in K's place —
decide, execute, report; no per-step approval. Method: **PCSEV**. Advisor =
**Gemini alone** (`ops/consult.py`, advisory). **Time to K = Thai (UTC+7) 24h**;
rails stay UTC.

## What this project is (K's goal)
"เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the agent**.
Scope = **4 channels** (FB, TikTok, YT `@aerismusicth`, Shopee). Roblox goals are
**PARKED**, never closed. **Brand = เพลงส้นทีนไรเนี่ย**, only in `branding.py`.
**Revenue gate = ch3**: 1,000 subs AND 4,000 watch-hours/12 mo; the metric is
**followers** — end every clip with `release.FOLLOW_ASK` + `FOLLOW_PROMISE`.

## Sound + clip quality (K)
**sfizz** not GM; `AX_REQUIRE_REAL_INSTRUMENTS=1` → a fallback **raises**.
**One FLOOR, every format/channel (K 2026-11-17): "ห้ามอัพขึ้นเด็ดขาด"**
`ops/clip_standard.py` = floor + per-format profile, gated at **every** upload
route, no override; `ops/thumb_standard.py` too (dead silence ≤3 s, VFR ≤2%).
**Bank clips = `ops/clip_lane.py --song <FULL STEM> --query "..." --seconds 58`**
→ `library/bank/`, QC 14/14; picker + shot numbers in archive.
QC is mechanical only — **Gemini review is OUT** (2026-11-20), pinned by
`test_no_gemini_gate_in_the_video_system`. **A gate nothing can pass is broken,
not strict**.

## Accounts (K 2026-11-14): AR's OWN mail, never K's
Flow Music/Gemini run on K's `aerismusic8`; K taps a QR once, then
`login_vault.py save` **immediately**.

**A ledger only knows what it wrote — audit the live surface.** 2026-11-21: ledger
had 2 entries, channel 92 uploads, 4 refused by code, ledger missed 2. **A publish
route needs the gate more than a render lane** (`song_to_page --post` had none).
**K settled those 4: leave them** — do not unpublish or re-litigate.
**A report must count artifacts, not inputs** (`genres.py --report` reads the
release, not the lyric plan).


## Environment + platform risks
- **Fresh pod: `scripts/bootstrap-pod.sh`**; MV links must be durable
  (`ops/mv_page.py --all`). Judge rail health from the **run history**.
- **FB = Graph API only** (K 2026-11-15); browser posting is off.
- **Vault = truth; a secret injects only when the command *names* it.**
- **Writes:** `GITHUB_TOKEN` is 403; push via KV `axsecrets:gh-workflow-token`
  (workflow files need its `workflow` scope). Reads work with `$AX_GH_TOKEN`.
- **A `work/*` ledger must be un-ignored (`!…`) or a rail re-posts every tick.**
- **A green run is not a finished job.** rc 4 + `UPLOAD_LIMIT_EXCEEDED` = the
  per-channel daily cap — a cap is a **retry**, not a failure.
- **Never decide on missing/stale data** — a blank/stale row is `data`, never a
  guess. **`videos.list` ≤50 ids.**
- **Bound every rail:** `timeout-minutes` + `cancel-in-progress: true`;
  `OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py --strict`.
- **`ops/HOLD.md` decides whether rails may run** (lifted 11-13; K's
  **posting stop** 2026-11-20 is `ops/PUBLISH-HOLD` → `hold_gate.active()`).

## Art + picking NEW work (detail in archive)
`shot_director.py` cuts **on the music**; `song_prune.py --release` keeps the newest
take; **pick an un-clipped song**; the **release** is the catalogue. MV = **one
picture per shot** (K 2026-11-21) → top up the library before rendering.

## Recovery
`$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (`axvault:readme`); a lost `work/*.json`
is in the event log.
