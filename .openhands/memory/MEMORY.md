# MEMORY — index

**How to use.** Injected every session; **capped at 6 KB** by `ops/memory_guard.py`.
Rules/pointers only — detail in `MEMORY-ARCHIVE.md` + daily logs. New learning →
today's log; promote only if it changes a decision; **move** superseded detail to
the archive. **Read `.openhands/CHARTER.md` first** — K's mandate (2026-10-31): AR
administers all of K's work; it holds the loop and priority queue.

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
100% free: no paid API, subscription or credits. Free routes only — login-only web
apps via the headful Chromium K signed into, open APIs, self-hosted tooling. **AR
never types a password.** Related: **AUDIO FIRST**; delete the duplicate and the
worthless, never archive it; K reviews a channel's first work; never rename a
channel without K's approval.

## Accounts (K, 2026-11-14): every tool uses AR's OWN mail
"เครื่องมือทุกอย่างใช้เมล์ตัวเองล็อคอิน รวมถึง agent ในทีม ไม่ต้องใช้เมล์ K".
AR mailbox = `araeris4770d7@fldubai.com` (mail.tm; `ops/ar_identity.py`). Flow
Music/Gemini need an AR *Google Account*; free signup is blocked by Google's
`crossflowverification` (QR/SMS) → K taps the QR once (2026-11-12.md).

## Roles and method (K, 2026-10-31)
- **K = final authority.** Every standing rule is K's.
- **AR = me.** I administer **all** of K's work in K's place — decide, execute,
  report; no per-step approval. Hand K only what needs a credential or authority
  only K holds.
- **Method: PCSEV** (Problem, Cause, Solution, Execute, Verify); `ops/consult.py`
  **is** a real gate (→ `consult-log.jsonl`).
- **Time format (K, 2026-11-12):** times shown to K use **Thai time (UTC+7)
  24-hour** — never UTC or AM/PM. Rails stay UTC.

## What this project is (K's goal)
"เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the agent**,
built from free cloud tools. Scope = **4 channels** (focus aeris938-2 = Facebook,
TikTok, YouTube `@aerismusicth`, Shopee Affiliate). Two goals in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` must never close as ordinary tasks: a
Roblox game anyone can enter and play, and real revenue from it (Roblox **PARKED**).
**Revenue gate = ch3 `@aerismusicth`** `UCm44BjAn03ruOF-WaA3ZRww`: **1,000 subs AND
4,000 watch-hours/12 mo**. Free lever = **weekly numbered long-form series**
(`volume_series.py` → Vol.N, ~75 min; scan 2026-11-15: winners = numbered long-form).

## The metric is followers (K, 2026-11-09)
Views without follows is the failure. Send every surface to the Page; end every
clip with `release.FOLLOW_ASK` + `FOLLOW_PROMISE` ("เพลงใหม่ทุกวัน").

## Environment facts that cost time
- **Fresh-pod recovery: `scripts/bootstrap-pod.sh`** — re-run after every pod.
- **24/7 runs on GitHub Actions, not the sandbox** (public repo → free minutes).
  Judge health from the **rail run history** (API), not `data/heartbeat.json`
  (stale 9 days once). Rails/topic: archive.
- **FB browser posting is OFF (K 2026-11-15: "ระบบออโต้เราไม่เนียนมันจับได้").**
  `crosspost.API_ONLY = {"facebook"}` — FB posts only via the Graph API and parks
  (rc 3, green) with no live token, never a browser. Revive needs a Meta System
  User token → `FB_PAGE_TOKEN`. A paused surface reports `note="paused"`.
- **Writes:** `GITHUB_TOKEN` is 403. Push with vault KV
  `axsecrets:gh-workflow-token` (dict, `.token`).
- **Desktop view = Live View** (`work-2`, port 12001; `bootstrap.py start_liveview`);
  X does not repaint, so noVNC freezes.
- **Thai text** lives only in `roblox/src/shared/Text.luau` +
  `music938-1/fonts/NotoSansThai.ttf`; without `fonts-thai-tlwg` the SVG renderer
  makes tofu silently. Burned ASS text has no emoji — use `•` / `»`.
- **`ops/websearch.py`** is the free web search (Tavily has no quota left).

## Real-instrument sound (K, 2026-11-09) — durable
The **sfizz** sampler, not the GM synth; `AX_REQUIRE_REAL_INSTRUMENTS=1` makes a
fallback **raise**. Beds pre-render on the pod (archive).

## Music video = public-domain film matched to the song (2026-11-13)
"วีดีโอต้องเหมาะกับเพลงและบทเพลงสิ" — *this* film for *this* song.
`music938-1/scripts/make_film_video.py` casts by `# MOOD:` and pulls the film
from archive.org (check `licenseurl`). `test_film_video` pins it.

## K-free status (2026-11-13) — audit in `ops/k_free_status.py`
**5/11 rails K-free | K once 2 | agent-revivable 2 | K repeatedly 1** (TikTok).
**"Blocked" usually meant "blocked on the route I tried first":** check the desktop
+ vault first. Watchdog alerts only on a *new* K-dependency.

## Loop health & platform risks
- **A green run is not a finished job.** The release rail reported success while
  YouTube refused every upload (2026-11-13/15: 0 videos, misread as a "reach"
  problem). `release.py` now returns rc 4 + `UPLOAD_LIMIT_EXCEEDED`;
  `heartbeat.collect()` pages when a rail's **latest run failed**. Read the log.
- **Never decide on missing/stale data** (2026-11-12): a blank/stale newest row is
  `data`, never a guess; `--assert-fresh` gates the dashboard rail. Detail: archive.
- **`videos.list` takes ≤50 ids/call** (past 50 → HTTP 400, once mislabeled
  "quota"). Chunk via `ops/yt_auth.get_videos`; a non-403 error must fail the rail.
- **YPP = 1,000 subs AND 4,000 watch-hours.** `goal_watch` reads the Studio scrape
  and names **retention** when the hour gate is further (2026-11-13: 8 subs vs
  23.5 h; 0% returning).
- Platform risks: `AKATH_CORE/OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py`
  (`--strict`); guard `.github/workflows/ax-risk-audit.yml`.

## Recovery
Lost rail/file: `$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (KV `axvault:readme`) or
`MEMORY-ARCHIVE.md`; a lost `work/*.json` is in the conversation event log.
