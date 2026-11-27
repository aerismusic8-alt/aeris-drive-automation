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
- **A bed is not a song: the compass filters BOTH**; argv slugs call
  `compass.require_publishable`; list and single-slug must agree.
- **The product is a SONG clip, not a narrated one** (`narration` only where K
  named it: `trivia`; `story` = **tool**). Old posted clips untouched.
- **`mv` has a rail** (`ax-music-mv`: 4K → media-938; publish stays in
  `release.py`); `film` still none. karaoke rail deleted.

## Genre = FUN ONLY — **five main lanes** (K 2026-11-21)
**Active: pop / rock / rap / hiphop / alternative** (`main_genres` in
`channel/genres.json`). Everything else PARKED = ห้ามอัพ (edm, synthpop, citypop,
เพื่อชีวิต …). **ทำทั้งช้าและเร็ว, ทุกเพลงต้องมีท่อนฮุกติดหู.**
**`lyrics-original/` (เพื่อชีวิต) — never publish.**
`genres.publishable()` fails closed at **every** publish path; `--list-songs`
stdout must stay pure (a log line piped to `shuf` killed the lane once).

## Roles and method (K 2026-10-31)
**K = final authority.** **AR = me**: I administer all of K's work in K's place —
decide, execute, report; no per-step approval. Method: **PCSEV**. Advisor =
**Gemini alone** (`ops/consult.py`, advisory). **Time to K = Thai (UTC+7) 24h**;
rails stay UTC. **A diagnosis with no method = "exhausted" forever** (2026-11-25).

## What this project is (K's goal)
"เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the agent**.
Scope = **4 channels** (FB, TikTok, YT `@aerismusicth`, Shopee). Roblox = **PARKED**. **Brand = เพลงส้นทีนไรเนี่ย**, only in `branding.py`.
**Revenue gate = ch3**: 1,000 subs AND 4,000 watch-hours/12 mo; clips end with
`release.FOLLOW_ASK` + `FOLLOW_PROMISE`.

## Sound + clip quality (K)
**sfizz** not GM; `AX_REQUIRE_REAL_INSTRUMENTS=1` → fallback **raises**.
**One FLOOR, every format/channel (K 2026-11-17): "ห้ามอัพขึ้นเด็ดขาด"**
`ops/clip_standard.py` = floor + per-format profile, gated at **every** upload
route, no override; `ops/thumb_standard.py` too (silence ≤3 s, VFR ≤2%).
**Bank clips = `ops/clip_lane.py --song <STEM> --query ... --seconds 58`** →
`library/bank/`, QC 14/14.
**A blank picture can still have ink** (`picture_std_min` 3.0/4.0); 19 clips
exceed the 6 % bar limit → fix shorts/karaoke/concert scrims.
QC is mechanical only — **Gemini review is OUT** (2026-11-20), pinned by
`test_no_gemini_gate_in_the_video_system`. **A gate nothing can pass is broken,
not strict**.

## Accounts (K 2026-11-14): AR's OWN mail, never K's
Flow Music/Gemini run on K's `aerismusic8`; K taps a QR once, then
`login_vault.py save` **immediately**.

**A ledger only knows what it wrote — audit the live surface** (archive). **A report counts artifacts, not inputs**
(`genres.py --report` reads the release).


## Environment + platform risks
- **Fresh pod: `scripts/bootstrap-pod.sh`**; MV links must be durable
  (`ops/mv_page.py --all`).
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
- **`ops/HOLD.md` decides whether rails may run**; K's **posting stop**
  (2026-11-20) is `ops/PUBLISH-HOLD` → `hold_gate.active()`.
- **11-26: the image bank was dead for 3 days** (6×120-min cancels, newest
  row 11-23): a stale page reset the exit test and cursors were saved only on
  a kept batch (PR #59). **Judge a harvest by the manifest, not the run
  list.** Volume preflight also needs `pull_media --only covers`;
  **TikTok has no token** — it needs K's developer app.

## Art + NEW work
`shot_director.py` cuts **on the music**; **pick an un-clipped song**; the
**release** is the catalogue.
**NO REPEATS, EVER (K 2026-11-21) — content, not names.** `ops/no_repeat.py` gates
every MV: audio SHA-256, lyric shingle ≥90%, picture SHA-1 vs `picture-ledger.json`;
<8 unused → refuse (fill the library). One palette per MV from 8. Keep
`music938-1/tests/run.py` green.

## Standing orders (K, 2026-11-26) — do not re-ask
**MV: ≤60 s or >600 s only.** 90–600 s is refused by `clip_standard.check()` via
`duration_verdict()` unless the slug is a registered special release
(`channel/special-releases.json`, **max 2/quarter**, reason + a ≤60 s hook cut
required; ships empty, unreadable = nothing allowed).
**Vol.4: hold until 2026-12-15** or ≥5 new publishable songs, then
`volume_series.deadline_decision()` → remaster (labelled, series number not
advanced). **Overlap >0.8 = absolute veto, every case, no date exempts it.**
A new publishable single ships as a ≤60 s clip immediately — never held for a
volume. **Title A/B ends 2026-12-18**: numbered wins → default single; hook wins
or ties → hook. A gap under 20% is **not** a result — run round 2.
**TikTok = pipeline test only**, no discovery credit until the app review passes;
`TT_POLICY_EMAIL` is an OpenHands secret K populates — if absent, stop and wait,
never substitute another address, never publish the policy. **The weekly audit may
re-run without asking** (`ax-yt-audit-weekly.yml`). Report if the pod recycles
more than 3× in a day (2 is tolerated).

## Recovery
`$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py`; a lost `work/*.json`
is in the event log.
