# MEMORY — index
**How to use.** Capped 6 KB (`ops/memory_guard.py`); rules/pointers only, detail in
`MEMORY-ARCHIVE.md` + daily logs. **Read `.openhands/CHARTER.md` first.**

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
100% free: no paid API, subscription or credits. Free routes only — login-only web
apps (K's Chromium), open APIs, self-hosted tooling. **AR never types a password.**
**AUDIO FIRST**; delete the duplicate/worthless, never archive it; K reviews a
channel's first work; never rename a channel without K's approval.

## Accounts (K 2026-11-14): every tool uses AR's OWN mail, not K's
AR mail (`ar_identity.py`) + self-creatable Nostr/Telegraph. Flow Music/Gemini =
K's `aerismusic8`; a QR once, then `login_vault.py save` **immediately**. A synth
bed has **no vocal** — Flow is the only real-song route. Detail: archive.

## Roles and method (K 2026-10-31)
- **K = final authority.** Every standing rule is K's.
- **AR = me.** I administer **all** of K's work in K's place — decide, execute,
  report; no per-step approval. Hand K only what needs a credential or authority
  only K holds.
- **Method: PCSEV.** **Advisor = Gemini alone** (K 2026-11-18); `ops/consult.py`
  is a real gate (→ `consult-log.jsonl`).
- **Time to K = Thai (UTC+7) 24-hour**, never UTC or AM/PM. Rails stay UTC.

## What this project is (K's goal)
"เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the agent**,
built from free cloud tools. Scope = **4 channels** (focus aeris938-2 = Facebook,
TikTok, YouTube `@aerismusicth`, Shopee Affiliate). Two goals in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` never close as ordinary tasks: a Roblox
game anyone can play, and real revenue from it (Roblox **PARKED**).
**Brand = เพลงส้นทีนไรเนี่ย** (handle `@aerismusicth`); the name lives only in
`music938-1/scripts/branding.py` — never hardcode it.
**Revenue gate = ch3**: **1,000 subs AND 4,000 watch-hours/12 mo**. The metric is
**followers** (K 2026-11-09): end every clip with `release.FOLLOW_ASK` +
`FOLLOW_PROMISE`.

**🎵 แนวช่อง = FUN ONLY** (K 2026-11-18 "ทำแนวสนุกอย่างเดียว"): pop/synthpop/edm/
rock/hiphop/rap/alternative. **PARKED = ห้ามอัพ**: lukthung ลูกทุ่ง, เพื่อชีวิต,
morlam, indie, lofi, rnb, jazz, acoustic, country, symphonic. **The 20
`lyrics-original/` songs are ALL เพื่อชีวิต — never publish them.**
Gate = `genres.publishable()`, fails closed, and runs at **every** publish path
(`yt_publish` needs `--song SLUG`/`--not-a-song WHY`, else refuses; `bank_publish`,
`clip_lane`, `compile_album.available_songs()` 46→27). `--list-songs` stdout must
stay pure — a log line piped to `shuf` killed the clip lane (2026-11-20).

## Environment facts that cost time
- **Fresh pod: `scripts/bootstrap-pod.sh`** — re-run after every pod.
- **MV links must be durable (K: "ลิงค์ตาย")** — `ops/mv_page.py --all`. Archive.
- **24/7 on GitHub Actions** (public repo → free minutes); judge health from the
  **rail run history**, not `heartbeat.json`.
- **FB = Graph API only (K 2026-11-15); browser OFF** (`axsecrets:fb-page-token`).
- **Vault = truth; a secret injects only when the command *names* it** (else 401).
- **Writes:** `GITHUB_TOKEN` is 403; push via KV `axsecrets:gh-workflow-token`
  (workflow files need its `workflow` scope). API reads work with `$AX_GH_TOKEN`.
- **Desktop = Live View** (`work-2`:12001); Thai `Text.luau` + `NotoSansThai.ttf`
  (else tofu); burned ASS has no emoji.
- **`ops/websearch.py`** = the free web search (Tavily has no quota).
- **A shell step failing "for no reason":** replay it with `bash -e -o pipefail`.
  An unmatched `grep` in `X=$(...)` returns 1 and `-e` kills the step before your
  error branch — add `|| true`.

## Sound + clip quality (K)
**sfizz** not GM; `AX_REQUIRE_REAL_INSTRUMENTS=1` → a fallback **raises**.
**One FLOOR, every format/channel (K 2026-11-17): "ห้ามอัพขึ้นเด็ดขาด"**
`ops/clip_standard.py` = floor + per-format profile, gated at **every** upload route,
no override; `ops/thumb_standard.py` too. `docs/clip-standard.md`. `short` (captions →
text floor) ≠ `vertical` (MV → none). Also gates dead silence (≤3 s) + VFR (≤2%).

## Retry lanes → ch3 (trivia + reactive)
`trivia_publish.py` + `reactive_publish.py` share one chokepoint; a cap = **retry**;
each `work/*` ledger must be un-ignored (`!…`) or it re-posts every tick.

## Loop health & platform risks
- **A green run is not a finished job.** rc 4 + `UPLOAD_LIMIT_EXCEEDED` = the
  per-channel daily cap, which clears over hours. Detail: archive.
- **`continue-on-error` + wrong step order = a silent broken artifact** — assert
  the order; repair at the chokepoint, never re-render by hand.
- **Never decide on missing/stale data** (2026-11-12): a blank/stale newest row is
  `data`, never a guess; `--assert-fresh` gates the dashboard rail.
- **`videos.list` ≤50 ids/call; YPP = 1,000 subs AND 4,000 watch-hours.**
- **Bound every rail:** `timeout-minutes` + `cancel-in-progress: true`. Risks:
  `OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py --strict`.


## Art + image bank (2026-11-19): our own code, no API
`genart.py` + `image_bank.py` shard → `media-938`; `image_library.py publish` →
**`scenes-938`** (`_fetch_scenes()` pulls). Commit the manifest only. Archive.

## The director (K 2026-11-20 "อยากได้ผู้กำกับภาพยนตร์")
`shot_director.py` cuts **on the music**: onset-snapped, shot length follows energy
(1.2-6 s), move never repeats. ffmpeg→numpy, no librosa. `--no-direct` = old grid.
**`zoompan d` = frames per INPUT frame** → loop at OUTPUT fps, `d=1`.
A green CI run is not proof a feature ran: read the log for its own line.

## Recovery
`$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (`axvault:readme`); a lost `work/*.json`
is in the event log.
