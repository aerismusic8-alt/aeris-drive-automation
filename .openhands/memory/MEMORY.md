# MEMORY — index
**Capped 6 KB** (`ops/memory_guard.py`): rules/pointers only, detail in
`MEMORY-ARCHIVE.md` + daily logs. **Read `.openhands/CHARTER.md` first.**

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
100% free: no paid API, subscription or credits. Free routes only — login-only web
apps (K's Chromium), open APIs, self-hosted tooling. **AR never types a password.**
**AUDIO FIRST**; delete the duplicate/worthless, never archive it; K reviews a
channel's first work; never rename a channel without K's approval.

## 🧭 THE COMPASS — the one direction for NEW work (K 2026-11-20)
`ops/compass.py` is the single answer to *which lane may produce what, at which
standard, into which folder*. **Read it before touching a clip lane; add a row
before adding a rail.** Row shape in archive; it **fails closed**.
- **`compass.songs(lane)` is the only way a lane lists songs**;
  `compass.is_publishable(slug)` is the single-slug form; `--check` must be
- **A bed is not a song: the compass filters BOTH**; argv slugs call
  `compass.require_publishable`; list and single-slug must agree.
- **The product is a SONG clip, not a narrated one** (`narration` only for
  `trivia`; `story` = **tool**). Old posted clips untouched.
- **`mv` has a rail** (`ax-music-mv`: 4K → media-938; publish stays in
  `release.py`); `film` still none. karaoke rail deleted.

## Genre = FUN ONLY — **five main lanes** (K 2026-11-21)
**Active: pop / rock / rap / hiphop / alternative** (`main_genres`). Everything
else PARKED = ห้ามอัพ. **ทุกเพลงต้องมีท่อนฮุกติดหู. `lyrics-original/` — never
publish.** `genres.publishable()` fails closed at **every** publish path;
`--list-songs` stdout stays pure (a log line piped to `shuf` killed the lane).

## Roles and method (K 2026-10-31)
**K = final authority. AR = me**: I administer K's work in K's place — decide,
execute, report; no per-step approval. Method **PCSEV**; advisor **Gemini alone**
(`ops/consult.py`, advisory). **Time to K = Thai (UTC+7) 24h**, rails UTC.
**A diagnosis with no method = "exhausted" forever**.

## What this project is (K's goal)
"เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the agent**.
Scope = **4 channels** (FB, TikTok, YT `@aerismusicth`, Shopee). Roblox = **PARKED**. **Brand = เพลงส้นทีนไรเนี่ย**, only in `branding.py`.
**Revenue gate = ch3**: 1,000 subs AND 4,000 watch-hours/12 mo; clips end with
`release.FOLLOW_ASK` + `FOLLOW_PROMISE`.

## Sound + clip quality (K)
**sfizz** not GM; `AX_REQUIRE_REAL_INSTRUMENTS=1` → fallback **raises**.
**One FLOOR, every format (K): "ห้ามอัพขึ้นเด็ดขาด"** — `ops/clip_standard.py`
(+`thumb_standard.py`) gates **every** upload route, no override. **Bank clip =
`ops/clip_lane.py --song <STEM> --query ... --seconds 58`** → `library/bank/`.
**A blank picture can still have ink** (`picture_std_min` 3.0/4.0). QC is
mechanical only — **Gemini review is OUT**, pinned by
`test_no_gemini_gate_in_the_video_system`. **A gate nothing can pass is broken.**

## Accounts (K 2026-11-14): AR's OWN mail, never K's
Flow Music/Gemini run on K's `aerismusic8`; K taps a QR once, then
`login_vault.py save` **immediately**. **A ledger only knows what it wrote —
audit the live surface. A report counts artifacts, not inputs** (`genres.py
--report` reads the release).


## Environment + platform risks
- **Fresh pod: `scripts/bootstrap-pod.sh`**; MV links must be durable
  (`ops/mv_page.py --all`).
- **FB = Graph API only**; browser posting off. **Vault = truth; a secret injects
  only when the command *names* it.**
- **Writes:** `GITHUB_TOKEN` is 403; push via KV `axsecrets:gh-workflow-token`
  (workflow files need its `workflow` scope). Reads work with `$AX_GH_TOKEN`.
- **A `work/*` ledger must be un-ignored (`!…`) or a rail re-posts every tick.**
- **A green run is not a finished job.** rc 4 + `UPLOAD_LIMIT_EXCEEDED` = the
  daily cap: a **retry**, not a failure.
- **Never decide on missing/stale data**; **`videos.list` ≤50 ids**.
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

## Standing orders (K, 2026-11-26) — never re-ask
**MV: ≤60 s / >600 s only**; 90–600 s refused by `clip_standard.duration_verdict()`
unless registered (`channel/special-releases.json`, 2/quarter, reason + ≤60 s hook
cut; empty = nothing allowed). **Vol.4: hold to 2026-12-15** or ≥5 new songs →
`volume_series.deadline_decision()`; **overlap >0.8 = absolute veto, always**.
New single ships ≤60 s at once. **A/B ends 2026-12-18** (numbered wins → default;
<20% gap = noise → round 2). **TikTok = pipeline test only**; `TT_POLICY_EMAIL`
is K's secret — absent = stop, never substitute, never publish. Weekly audit may
re-run unasked; report a pod recycling >3×/day.

## Recovery
`$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py`; a lost `work/*.json`
is in the event log.
