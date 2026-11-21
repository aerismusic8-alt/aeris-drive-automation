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
- **A bed is not a song: the compass filters BOTH; a slug on argv must ask
  `compass.require_publishable(slug)`.** The list and single-slug forms must
  never disagree — four beds sat in every lane until 2026-11-21.
- **`pull_media` must never overwrite a differing local file** — the release
  lags an upload, so a newer render exists nowhere else. Report it; `--force`.
- **The product is a SONG clip, not a narrated one** (`narration` only where K
  asked by name: `trivia`; `story` is a **tool**). Old posted clips untouched.
- **Known gap:** `mv`/`film` have `rail: None` — no workflow renders an MV. Do
  not claim an MV ships.

## Genre = FUN ONLY (K 2026-11-18 "ทำแนวสนุกอย่างเดียว")
**Active:** pop/synthpop/edm/rock/hiphop/rap/alt. **PARKED = ห้ามอัพ:** lukthung,
เพื่อชีวิต, morlam, indie, lofi, rnb, jazz, acoustic, country, symphonic.
**The 20 `lyrics-original/` songs are ALL เพื่อชีวิต — never publish them.**
`genres.publishable()` fails closed at **every** publish path; `--list-songs`
stdout must stay pure (a log line piped to `shuf` killed the lane).

## Roles and method (K 2026-10-31)
**K = final authority.** **AR = me**: I administer all of K's work in K's place —
decide, execute, report; no per-step approval. Method: **PCSEV**. Advisor =
**Gemini alone** (`ops/consult.py`, advisory). **Time to K = Thai (UTC+7) 24h**;
rails stay UTC.

## What this project is (K's goal)
"เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the agent**,
from free cloud tools. Scope = **4 channels** (aeris938-2 = Facebook, TikTok,
YouTube `@aerismusicth`, Shopee Affiliate). Two goals in the task registry never
close as ordinary tasks: a Roblox game anyone can play, and revenue from it
(Roblox **PARKED**). **Brand = เพลงส้นทีนไรเนี่ย** — only in `branding.py`.
**Revenue gate = ch3**: 1,000 subs AND 4,000 watch-hours/12 mo; the metric is
**followers** — end every clip with `release.FOLLOW_ASK` + `FOLLOW_PROMISE`.

## Sound + clip quality (K)
**sfizz** not GM; `AX_REQUIRE_REAL_INSTRUMENTS=1` → a fallback **raises**.
**One FLOOR, every format/channel (K 2026-11-17): "ห้ามอัพขึ้นเด็ดขาด"**
`ops/clip_standard.py` = floor + per-format profile, gated at **every** upload
route, no override; `ops/thumb_standard.py` too (dead silence ≤3 s, VFR ≤2%).
**Bank clips = `ops/clip_lane.py --song X --query "..." --seconds 58`** → into
`library/bank/` (gitignored; rides media-938), QC 14/14. Picker sorts bank rows
by width **before** the pool cap (else a 4K row never enters); detail in archive.
QC is mechanical only — **Gemini review is OUT** (2026-11-20), pinned by
`test_no_gemini_gate_in_the_video_system`. **A gate nothing can pass is broken,
not strict** — the verdict decides, the score is only a sanity floor.

## Accounts (K 2026-11-14): AR's OWN mail, never K's
Flow Music/Gemini run on K's `aerismusic8`; K taps a QR once, then
`login_vault.py save` **immediately**.

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

## Art, director, and picking NEW work
`genart.py` + `image_bank.py` → `media-938`, manifest only. `shot_director.py`
cuts **on the music**; MV shot = whole beats, 2.8–5.5 s, **≤22 cuts/min any
tempo** (numbers in archive); `ops/song_prune.py --release` keeps the newest.
**Pick an un-clipped song (K: "ก็ไปวนเอาของเก่ามาทำ")** — only asset filenames
tell the truth; the **release** is the catalogue, a local cache must not narrow it.

## Recovery
`$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (`axvault:readme`); a lost `work/*.json`
is in the event log.
