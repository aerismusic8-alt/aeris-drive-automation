# MEMORY — index
**How to use.** Capped 6 KB (`ops/memory_guard.py`); rules/pointers only, detail in
`MEMORY-ARCHIVE.md` + daily logs. **Read `.openhands/CHARTER.md` first.**

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
100% free: no paid API, subscription or credits. Free routes only — login-only web
apps (K's Chromium), open APIs, self-hosted tooling. **AR never types a password.**
**AUDIO FIRST**; delete the duplicate/worthless, never archive it; K reviews a
channel's first work; never rename a channel without K's approval.

## Accounts (K 2026-11-14): AR's OWN mail, never K's
AR mail (`ar_identity.py`) + self-creatable Nostr/Telegraph. Flow Music/Gemini run
on K's `aerismusic8`; K taps a QR once, then `login_vault.py save` **immediately**.
A synth bed has **no vocal** — Flow is the only real-song route.

## Roles and method (K 2026-10-31)
- **K = final authority.** Every standing rule is K's.
- **AR = me.** I administer **all** of K's work in K's place — decide, execute,
  report; no per-step approval. Hand K only what needs a credential or authority
  only K holds.
- **Method: PCSEV.** **Advisor = Gemini alone** (K 2026-11-18); `ops/consult.py`
  → `consult-log.jsonl`. Advisory only — see the gate line.
- **Time to K = Thai (UTC+7) 24-hour**, never UTC or AM/PM. Rails stay UTC.

## What this project is (K's goal)
"เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the agent**,
built from free cloud tools. Scope = **4 channels** (aeris938-2 = Facebook, TikTok,
YouTube `@aerismusicth`, Shopee Affiliate). Two goals in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` never close as ordinary tasks: a Roblox
game anyone can play, and revenue from it (Roblox **PARKED**).
**Brand = เพลงส้นทีนไรเนี่ย**; the name lives only in `music938-1/scripts/branding.py`.
**Revenue gate = ch3**: 1,000 subs AND 4,000 watch-hours/12 mo; the metric is
**followers** — end every clip with `release.FOLLOW_ASK` + `FOLLOW_PROMISE`.
**🎵 FUN ONLY** (K 2026-11-18): pop/synthpop/edm/rock/hiphop/rap/alt.
**PARKED = ห้ามอัพ**: lukthung, เพื่อชีวิต, morlam, indie, lofi, rnb, jazz,
acoustic, country, symphonic. **The 20 `lyrics-original/` songs are ALL เพื่อชีวิต
— never publish them.** Gate = `genres.publishable()`, fails closed, at **every**
publish path (`yt_publish` needs `--song SLUG`/`--not-a-song WHY`; also
`bank_publish`, `clip_lane`, `compile_album.available_songs()` 46→27).
`--list-songs` stdout must stay pure — a log line piped to `shuf` killed the lane.

## Environment facts that cost time
- **Fresh pod: `scripts/bootstrap-pod.sh`** — re-run after every pod.
- **MV links must be durable (K: "ลิงค์ตาย")** — `ops/mv_page.py --all`.
- **24/7 on GitHub Actions** (public repo → free minutes); judge health from the
  **rail run history**, not `heartbeat.json`.
- **FB = Graph API only (K 2026-11-15); browser OFF** (`axsecrets:fb-page-token`).
- **Vault = truth; a secret injects only when the command *names* it** (else 401).
- **Writes:** `GITHUB_TOKEN` is 403; push via KV `axsecrets:gh-workflow-token`
  (workflow files need its `workflow` scope). API reads work with `$AX_GH_TOKEN`.
- **Desktop = Live View** (`work-2`:12001); Thai `Text.luau` + `NotoSansThai.ttf`
  (else tofu); burned ASS has no emoji. `ops/websearch.py` = free search.

## Sound + clip quality (K)
**sfizz** not GM; `AX_REQUIRE_REAL_INSTRUMENTS=1` → a fallback **raises**.
**One FLOOR, every format/channel (K 2026-11-17): "ห้ามอัพขึ้นเด็ดขาด"**
`ops/clip_standard.py` = floor + per-format profile, gated at **every** upload
route, no override; `ops/thumb_standard.py` too. `short` (captions → text floor) ≠
`vertical` (MV → none). Also gates dead silence (≤3 s) + VFR (≤2%).

## Gemini review is OUT of the video system (K 2026-11-20)
"ตัดการตรวจสอบของ gemini ออกจากระบบสร้างวีดีโอใหม่เลย" — `gemini_gate` was
fail-closed on every render + upload route; now **optional** (hand tool only).
**QC stays and blocks**: `clip_standard` + `genre_gate` + `thumb_standard` — they
measure the file and run anywhere; the review needed a signed-in desktop, so on a
runner it could never pass. Pinned by `test_no_gemini_gate_in_the_video_system`.

## Motion: Dreamina video VIP-gated; HF Wan = free i2v
Dreamina **images work**, **video VIP-gated**. Free i2v = `make_motion.py` HF Wan.
Detail: `docs/dreamina-access.md`.

## Retry lanes → ch3 (trivia + reactive)
`trivia_publish.py` + `reactive_publish.py` — one chokepoint; a cap = **retry**;
each `work/*` ledger must be un-ignored (`!…`) or it re-posts every tick.
## Loop health & platform risks
- **A green run is not a finished job.** rc 4 + `UPLOAD_LIMIT_EXCEEDED` = the
  per-channel daily cap; clears over hours, so a cap is a **retry**.
- **Never decide on missing/stale data** (2026-11-12): a blank/stale newest row is
  `data`, never a guess; `--assert-fresh` gates the dashboard rail.
- **`videos.list` ≤50 ids/call; YPP = 1,000 subs AND 4,000 watch-h.**
- **Bound every rail:** `timeout-minutes` + `cancel-in-progress: true`; see
  `OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py --strict`.

## Art + image bank: our own code, no API
`genart.py` + `image_bank.py` shard → `media-938`; `image_library.py publish` →
`scenes-938`. Commit the manifest only.

## The director (K 2026-11-20 "อยากได้ผู้กำกับภาพยนตร์")
`shot_director.py` cuts **on the music**: onset-snapped, shot length follows energy
(1.2-6 s), the move never repeats. **`zoompan d` = frames per INPUT frame** → loop
at OUTPUT fps, `d=1`. A green CI run is not proof a feature ran: read its own log
line. Detail: archive.

## Recovery
`$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (`axvault:readme`); a lost `work/*.json`
is in the event log.
