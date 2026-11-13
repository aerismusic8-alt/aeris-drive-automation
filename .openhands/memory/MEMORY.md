# MEMORY — index

**How to use.** Injected into every session; **capped at 6 KB** by
`ops/memory_guard.py`. Rules and pointers only — full detail is in
`MEMORY-ARCHIVE.md` and the daily logs `YYYY-MM-DD.md`. New durable learning goes
to today's log first; promote a line here only if it changes a future decision,
and **move** superseded detail to the archive, never delete it.

**Read `.openhands/CHARTER.md` first** — K's mandate (2026-10-31) that AR
administers all of K's work, plus the loop and live priority queue.

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
Everything must be 100% free: no paid API, subscription or credit pack. Free
routes only — login-only web apps driven through the headful Chromium K signed
into, open APIs, self-hosted tooling. **AR never types a password.** Related K
rules: **AUDIO FIRST**; delete the duplicate and the worthless, never archive it;
K reviews a channel's first work; never rename a channel without K's approval.

## Roles and method (K, 2026-10-31)
- **K = final authority.** Every standing rule is K's.
- **AR = me.** I administer **all** of K's work in K's place — decide, execute,
  report; no per-step approval. Hand a decision to K only when it needs a
  credential or authority only K holds.
- **Method: PCSEV** (Problem, Cause, Solution, Execute, Verify) — a habit, not
  machine-enforced; `ops/consult.py` **is** a real gate. Consult before deciding on
  any non-trivial problem (`ops/consult.py "…"` → `consult-log.jsonl`).
- **Time format (K, 2026-11-12):** times shown to K use **Thai time (UTC+7)
  24-hour** (`2026-11-12 19:05`) — never UTC or AM/PM. Rails stay UTC.

## What this project is (K's goal)
K: "เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the
agent**, built from free cloud tools. Scope = **4 channels**. Two goals in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` must never close as ordinary tasks: a
Roblox game anyone can enter and play, and real revenue from it (Roblox
**PARKED**). Focus (aeris938-2) = 4 jobs: Facebook, TikTok, YouTube
`@aerismusicth`, Shopee Affiliate. **Revenue gate = ch3 `@aerismusicth`**
`UCm44BjAn03ruOF-WaA3ZRww`: YouTube's **1,000 subs AND 4,000 watch-hours/12 mo**.
Free lever = long-form volume (`compile_album.py`; ~1 h/view vs 3 min).
**แนวเพลง (K, 2026-11-13):** พักลูกทุ่ง/เพื่อชีวิต — เน้น **ป็อป/แดนซ์(edm)/ร็อก**
(`music938-1/channel/genres.json` `status: parked`; `genres.is_parked/active`).

## The metric is followers (K, 2026-11-09)
Views without follows is the failure. Send every surface to the Page; end every
clip with `release.FOLLOW_ASK` + `release.FOLLOW_PROMISE` ("เพลงใหม่ทุกวัน").
A post whose `reach≈2` is a repost of a Page clip — stop it.

## Environment facts that cost time
- **Fresh-pod recovery: `scripts/bootstrap-pod.sh`** — re-run after every pod
  (the `.pth` is non-durable). Detail: archive.
- **24/7 runs on GitHub Actions, not the sandbox** (public repo → free minutes).
  Rails: `ax-music-release` 07:00 UTC, `ax-music-crosspost` 2-hourly,
  `ax-rail-watchdog` :15, `ax-music-dashboard` 08:30 UTC (ntfy
  `ax-ar-aeris-9f3k7q`). Judge loop health from the **rail run history** (API), not
  `data/heartbeat.json` — it was 9 days stale while the pod was fine.
- **A dead browser session is the crosspost rail's top failure** (FB serves the
  logged-out page while still holding `c_user`/`xs`, so a cookie check lies).
  Fix: `python3 ops/fb_relogin.py --push-secret`. Detail: archive.
- **Writes:** `GITHUB_TOKEN` is 403. Push with the vault KV
  `axsecrets:gh-workflow-token` (dict, `.token`) in the URL
  `https://x-access-token:<tok>@github.com/...`. Detail: archive.
- **Desktop view = Live View** (`work-2` host, port 12001; `bootstrap.py`
  `start_liveview`). The X screen does not repaint here, so noVNC is frozen.
- **Thai text** lives only in `roblox/src/shared/Text.luau` (Roblox) and
  `music938-1/fonts/NotoSansThai.ttf` (video); without `fonts-thai-tlwg` the SVG
  renderer makes tofu silently. Burned ASS text has no emoji glyph — use `•` / `»`.
- **`ops/websearch.py`** is the free web search (Tavily has no quota left).

## Real-instrument sound (K, 2026-11-09) — durable
K rejected the ffmpeg tone synth and GM SoundFont as "fake": use the **sfizz**
sampler (`install-sfizz.sh`); `AX_REQUIRE_REAL_INSTRUMENTS=1` makes a GM fallback
**raise**. Beds pre-render on the pod → `media-938` (detail: archive).

## Music video = public-domain film, matched to the song (K, 2026-11-13)
K: "วีดีโอต้องเหมาะกับเพลงและบทเพลงสิ" — *this* film for *this* song.
`music938-1/scripts/make_film_video.py`: cast by `# MOOD:`, cut and grade by
section, film from archive.org (check `licenseurl`). `videos.insert` has its own
~100/day bucket, so it uploads while other calls 403; secrets inject only when the
command names the key. `test_film_video` pins it.

## Loop health & platform risks
- Judge "does the loop reach the goal on its own?" from the **rail run history**,
  not `data/heartbeat.json`. A red rail is the loop failing to walk.
- **Never decide on missing/stale data** (2026-11-12 panel, quorum PASS): a blank
  or stale newest row is `data`, never a guess; `--assert-fresh` gates the
  dashboard rail. Detail: archive.
- **`videos.list` takes ≤50 ids/call** (past 50 → HTTP 400, once mislabeled
  "quota"). Chunk via `ops/yt_auth.get_videos`; a non-403 error must fail the rail.
- Platform risks: `AKATH_CORE/OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py`
  (`--strict`); the 24/7 guard is `.github/workflows/ax-risk-audit.yml`.

## Recovery
If a rail or file vanishes: `$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (KV
`axvault:readme`), or `MEMORY-ARCHIVE.md`. A lost `music938-1/work/*.json` is in
the conversation event log (`file_editor` `create` carries the text).
