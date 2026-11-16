# MEMORY — index

**How to use.** Injected every session; **capped at 6 KB** by `ops/memory_guard.py`.
Rules/pointers only — detail in `MEMORY-ARCHIVE.md` + daily logs. New learning →
today's log; promote only if it changes a decision; **move** superseded detail to
the archive. **Read `.openhands/CHARTER.md` first** — K's mandate (2026-10-31).

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
100% free: no paid API, subscription or credits. Free routes only — login-only web
apps (K's Chromium), open APIs, self-hosted tooling. **AR
never types a password.** Related: **AUDIO FIRST**; delete the duplicate and the
worthless, never archive it; K reviews a channel's first work; never rename a
channel without K's approval.

## Accounts (K, 2026-11-14): every tool uses AR's OWN mail
"เครื่องมือทุกอย่างใช้เมล์ตัวเองล็อคอิน รวมถึง agent ในทีม ไม่ต้องใช้เมล์ K".
AR mailbox = `araeris4770d7@fldubai.com` (mail.tm; `ops/ar_identity.py`).
**AR self-creatable:** **Nostr** (own keypair, `AR_NOSTR_NSEC`, live rail
`ops/announce_releases.py`) and **Telegraph** (`ops/ar_telegraph.py`, no captcha).
Flow Music/Gemini need an AR *Google Account* → K taps a QR once.

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
**Revenue gate = ch3 `@aerismusicth`**: **1,000 subs AND 4,000 watch-hours/12 mo**.
Free lever = **weekly numbered long-form series** (`volume_series.py`).

## The metric is followers (K, 2026-11-09)
Views without follows is the failure. End every clip with `release.FOLLOW_ASK` +
`FOLLOW_PROMISE` ("เพลงใหม่ทุกวัน").

## Environment facts that cost time
- **Fresh-pod recovery: `scripts/bootstrap-pod.sh`** — re-run after every pod.
- **MV links must be durable (K: "ลิงค์ตาย").** GitHub Pages `site-aeris-music`,
  auto-published by its own `ax-mv-pages` workflow (`ops/mv_page.py --all`, skips
  existing pages; `slug`/`force` dispatch rebuilds one). A /tmp preview dies on
  recycle. Song metadata = its lyric header, not a songs.json.
- **24/7 runs on GitHub Actions, not the sandbox** (public repo → free minutes).
  Judge health from the **rail run history** (API), not `data/heartbeat.json`.
- **FB browser posting is OFF (K 2026-11-15: "ระบบออโต้เราไม่เนียนมันจับได้").**
    FB posts only via the Graph API (`crosspost.API_ONLY`); parks green otherwise.
- **Writes:** `GITHUB_TOKEN` is 403; push via vault KV `axsecrets:gh-workflow-token`
  (needs `OPENHANDS_API_KEY`; workflow files need it too).
- **Desktop view = Live View** (`work-2`, port 12001; X does not repaint).
- **Thai text** lives only in `roblox/src/shared/Text.luau` +
  `music938-1/fonts/NotoSansThai.ttf`; without `fonts-thai-tlwg` the SVG renderer
  makes tofu silently. Burned ASS text has no emoji — use `•` / `»`.
- **`ops/websearch.py`** is the free web search (Tavily has no quota left).

## Real-instrument sound (K, 2026-11-09) — durable
The **sfizz** sampler, not the GM synth; `AX_REQUIRE_REAL_INSTRUMENTS=1` makes a
fallback **raise** (beds pre-render on the pod; archive).

## Music video = public-domain film matched to the song (2026-11-13)
`make_film_video.py` casts the film by `# MOOD:` from archive.org (check
`licenseurl`); the picture must answer the lyric (K, 2026-11-16: a warm song got a
Western → `warm` recast to the musical). **Release wiring (2026-11-16):**
`release.py plan()` ships the MV as the long-form release when one exists
(`mv_files`; film>mv; -hook/-vertical excluded); lyric render is the fallback;
`describe()` marks `มิวสิควีดีโอ`. Free-media rails + `test_film_video`: archive.

## K-free status (2026-11-13) — audit in `ops/k_free_status.py`
"Blocked" = "blocked on the route I tried first" (desktop+vault first). Scoreboard: archive.

## Loop health & platform risks
- **A green run is not a finished job.** `release.py` returns rc 4 +
  `UPLOAD_LIMIT_EXCEEDED`; `heartbeat` pages when a rail's latest run failed.
  The cap is **per-channel new-videos/day** (unverified territory), clears over
  hours, not at the 08:00 UTC API reset; a burst extends it. Read the log.
- **Never decide on missing/stale data** (2026-11-12): a blank/stale newest row is
  `data`, never a guess; `--assert-fresh` gates the dashboard rail. Detail: archive.
- **`videos.list` takes ≤50 ids/call** (past 50 → HTTP 400, once mislabeled
  "quota"). Chunk via `ops/yt_auth.get_videos`; a non-403 error must fail the rail.
- **YPP = 1,000 subs AND 4,000 watch-hours.** `goal_watch` reads the Studio scrape
  and names **retention** when the hour gate is further (detail: archive).
- Platform risks: `AKATH_CORE/OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py`
  (`--strict`); guard `.github/workflows/ax-risk-audit.yml`.

## Recovery
Lost rail/file: `$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (KV `axvault:readme`) or
`MEMORY-ARCHIVE.md`; a lost `work/*.json` is in the conversation event log.
