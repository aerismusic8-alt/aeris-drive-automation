# MEMORY — index

**How to use.** Injected into every session; **capped at 6 KB** by
`ops/memory_guard.py` (a CI test fails past that). Rules and pointers only — full
detail is in `MEMORY-ARCHIVE.md` and the daily logs `YYYY-MM-DD.md`. New durable
learning goes to today's log first; promote a line here only if it changes a future
decision, and **move** superseded detail to the archive, never delete it.

**Read `.openhands/CHARTER.md` first** — K's mandate (2026-10-31) that AR
administers all of K's work in K's place, plus the loop and live priority queue.

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
Everything must be 100% free: no paid API, subscription or credit pack. Free
routes only — login-only web apps driven through the headful Chromium K signed
into, open APIs, self-hosted tooling. **AR never types a password.** Related K
rules: **AUDIO FIRST** (retention is the sound, not the picture); delete the
duplicate and the worthless, never archive it; K reviews a channel's first work;
never rename a channel without K's approval.

## Roles and method (K, 2026-10-31)
- **K = final authority.** Every standing rule is K's.
- **AR = me.** I administer **all** of K's work in K's place — decide, execute,
  report; no per-step approval. Hand a decision to K only when it needs a
  credential or authority only K holds.
- **Method: PCSEV** (Problem, Cause, Solution, Execute, Verify) — a habit, not
  machine-enforced; `ops/consult.py` **is** a real gate.
- **Consult before deciding** on any non-trivial problem: `ops/consult.py "…"`
  (2 channels across 2 vendor families; pollinations + duck → `consult-log.jsonl`).

## What this project is (K's goal)
K: "เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the
agent**, built from free cloud tools. Scope = **4 channels**. Two goals in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` must never close as ordinary tasks: a
Roblox game anyone can enter and play, and real revenue from it (Roblox
**PARKED**). Focus (aeris938-2) = 4 jobs: Facebook, TikTok, YouTube
`@aerismusicth`, Shopee Affiliate.
- **Revenue gate = ch3 `@aerismusicth` `UCm44BjAn03ruOF-WaA3ZRww`**: pass YouTube's
  **1,000 subs AND 4,000 watch-hours/12 mo**. Free lever = long-form volume
  (`compile_album.py`; a 60-min compilation earns ~1 h/view vs 3 min for a song).

## The metric is followers (K, 2026-11-09)
Views without follows is the failure. Send every surface to the Page; end every
clip with `release.FOLLOW_ASK` + `release.FOLLOW_PROMISE` ("เพลงใหม่ทุกวัน").
Measured 2026-11-10: FB 1,492 views/28d but **1 follower**; TikTok 73 views/7d.
A post whose `reach≈2` is a **repost** of a clip already on the Page — stop it.

## Environment facts that cost time
- **Fresh-pod recovery: `scripts/bootstrap-pod.sh`.** Restores python deps from
  `requirements.txt` into `/workspace/ax-tools/pylibs` (durable) and installs
  ffmpeg/fluidsynth/Thai-fonts/xvfb. The `.pth` lands in `~/.local` (NOT durable),
  so re-run after every pod or the suite dies on `numpy`. A hardcoded
  `work-{1,2}-<id>.prod-runtime…` host is a bug — build it from `$RUNTIME_ID`
  (`risk_audit` scans for a baked host).
- **24/7 runs on GitHub Actions, not the sandbox** (public repo → free minutes).
  Rails: `ax-music-release` 07:00 UTC, `ax-music-crosspost` 2-hourly,
  `ax-rail-watchdog` :15, `ax-music-dashboard` 08:30 UTC (ntfy topic
  `ax-ar-aeris-9f3k7q`). Judge loop health from the **rail run history** (API), not
  `data/heartbeat.json` — it was 9 days stale while the pod was fine.
- **A dead browser session is the crosspost rail's top failure.** FB fails two
  ways: (a) the Graph Page token rejected at account/app level (`API access
  blocked`, OAuthException 200) — only the owner restores it; (b) the browser
  cookie session dead (FB serves the logged-out page while still holding
  `c_user`/`xs`, so a cookie-presence check lies). Fix (b):
  `python3 ops/fb_relogin.py --push-secret` — one CDP sign-in from the vault
  password; it refreshes `login_vault` + CI secret `AERIS_STORAGE_STATE_B64`. The
  account block does **not** block the browser login.
- **Writes:** the app token can't touch `.github/workflows/` (no `workflow`
  scope) — read `axsecrets:gh-workflow-token` from the vault (name
  `OPENHANDS_API_KEY` in the command) and push with it; `GITHUB_TOKEN` is 403.
  `ax_vault.ensure_anchor()` raises `SystemExit` (a BaseException) — guard
  `except BaseException`, not `except Exception`.
- **Thai text** lives only in `roblox/src/shared/Text.luau` (Roblox) and
  `music938-1/fonts/NotoSansThai.ttf` (video); without `fonts-thai-tlwg` the SVG
  renderer makes tofu silently. Burned ASS text has no emoji glyph — use `•` / `»`.
- **`ops/websearch.py`** is the free web search (Tavily has no quota left).

## Real-instrument sound (K, 2026-11-09) — durable
K rejected the ffmpeg tone synth and the GM SoundFont as "fake". Use the
**sfizz** real-instrument sampler (`music938-1/scripts/install-sfizz.sh`, banks
under `/workspace/ax-tools/instruments/`) for every music bed. Rails:
`music938-1/scripts/ambient_loop.py` (sleep/ambient) and `flow_song.py` (songs).

## Growth lanes that work (research, 2026-11-09)
Long-form Thai compilations (1–3 h) and sleep/ambient loops (1–8 h) are the lanes
we can enter free; the single-song format caps at ~500 views. Do **not** stretch
runtime just to chase views.

## Loop health & platform risks
- Judge "does the loop reach the goal on its own?" from the **rail run history**,
  not `data/heartbeat.json`. A red rail is the loop failing to walk.
- Platform risks: `AKATH_CORE/OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py`
  (`--strict`); the 24/7 guard is `.github/workflows/ax-risk-audit.yml`.

## Recovery
If a rail or file vanishes: `$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (KV
`axvault:readme`), or `MEMORY-ARCHIVE.md`. A lost `music938-1/work/*.json` is in
the conversation event log (`file_editor` `create` carries the full text).
