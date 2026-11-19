# MEMORY — index

**How to use.** Capped at 6 KB (`ops/memory_guard.py`). Rules/pointers only —
detail in `MEMORY-ARCHIVE.md` + daily logs. **Read `.openhands/CHARTER.md` first.**

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
100% free: no paid API, subscription or credits. Free routes only — login-only web
apps (K's Chromium), open APIs, self-hosted tooling. **AR never types a password.**
Related: **AUDIO FIRST**; delete the duplicate/worthless, never archive it; K
reviews a channel's first work; never rename a channel without K's approval.

## Accounts (K, 2026-11-14): every tool uses AR's OWN mail, not K's
AR mailbox = `araeris4770d7@fldubai.com` (mail.tm; `ops/ar_identity.py`).
AR self-creatable: **Nostr** (`AR_NOSTR_NSEC`), **Telegraph** (`ops/ar_telegraph.py`).
Flow Music/Gemini = K's account `aerismusic8` (AR never types a password). K taps a
QR once, then `login_vault.py save` **immediately** (session ~1 day). A synth bed has
**no vocal**; Flow is the only real-song route.

## Roles and method (K, 2026-10-31)
- **K = final authority.** Every standing rule is K's.
- **AR = me.** I administer **all** of K's work in K's place — decide, execute,
  report; no per-step approval. Hand K only what needs a credential or authority
  only K holds.
- **Method: PCSEV** (Problem, Cause, Solution, Execute, Verify). **Advisor =
  Gemini alone (K, 2026-11-18): "ทีมที่ปรึกษาให้ใช้ gemini คนเดียวพอ" — when stuck,
  ask Gemini and follow its advice**; `ops/consult.py` is a real gate
  (→ `consult-log.jsonl`), panel `["gemini"]`, floor 1.
- **Time to K = Thai (UTC+7) 24-hour**, never UTC or AM/PM. Rails stay UTC.

## What this project is (K's goal)
"เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands" — the deliverable is **the agent**,
built from free cloud tools. Scope = **4 channels** (focus aeris938-2 = Facebook,
TikTok, YouTube `@aerismusicth`, Shopee Affiliate). Two goals in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` must never close as ordinary tasks: a
Roblox game anyone can enter and play, and real revenue from it (Roblox **PARKED**).
**Brand = เพลงส้นทีนไรเนี่ย** (handle `@aerismusicth`); the name lives only in
`music938-1/scripts/branding.py` — never hardcode it.
**Revenue gate = ch3**: **1,000 subs AND 4,000 watch-hours/12 mo**. The metric is
**followers** (K 2026-11-09): end every clip with `release.FOLLOW_ASK` +
`FOLLOW_PROMISE`.

## Environment facts that cost time
- **Fresh-pod recovery: `scripts/bootstrap-pod.sh`** — re-run after every pod.
- **MV links must be durable (K: "ลิงค์ตาย")** — `ops/mv_page.py --all`.
  Detail: archive.
- **24/7 runs on GitHub Actions** (public repo → free minutes); judge health from
  the **rail run history**, not `heartbeat.json`.
- **FB = Graph API only (K 2026-11-15); browser OFF.** `api-only`; vault
  `axsecrets:fb-page-token`; lanes in `crosspost.py`.
- **Vault = source of truth; a secret injects only when the command *names* it.**
- **Writes:** `GITHUB_TOKEN` is 403; push via KV `axsecrets:gh-workflow-token`
  (workflow files need its `workflow` scope).
- **Desktop = Live View** (`work-2`:12001); Thai text `Text.luau` +
  `NotoSansThai.ttf` (else tofu); burned ASS has no emoji.
- **Gemini (`gemini_gate.py`)**: no pass = no upload — but **its score is NOT the
  judge** (2026-11-19): clean clip 5 FAIL, captionless 7 PASS. Gate = rules + K.
- **`ops/websearch.py`** is the free web search (Tavily has no quota left).

## Sound + clip quality (K)
**sfizz** sampler, not GM; `AX_REQUIRE_REAL_INSTRUMENTS=1` → a fallback **raises**.
**One FLOOR, every format/channel (2026-11-17): "ห้ามอัพขึ้นเด็ดขาด".**
`ops/clip_standard.py` = floor + a per-format profile, gated at **every** upload
route, no override; `ops/thumb_standard.py` too. `docs/clip-standard.md`.
`short` (captions → text floor) ≠ `vertical` (MV → none); unnamed 9:16 permissive.
Also gates dead silence (≤3 s) + VFR (≤2%), both invisible to LUFS.

## Retry lanes → ch3 (trivia + reactive)
`trivia_publish.py` + `reactive_publish.py` share one chokepoint; a cap = **retry**,
not failure; each `work/*` ledger must be un-ignored (`!…`) or it re-posts every tick.

## Loop health & platform risks
- **A green run is not a finished job.** `release.py` rc 4 + `UPLOAD_LIMIT_EXCEEDED`;
  `heartbeat` pages on a failed latest run. The cap is **per-channel new-videos/day**,
  clears over hours, not at the 08:00 UTC reset.
- **`continue-on-error` + a wrong step order = a silent broken artifact** — the
  produce rail pulled beds *after* the produce step, so every song shipped
  `audio: none` while green: gate the artifact, assert the order.
- **A derived artifact outlives its source** — re-mastering leaves older clips
  clipped and the fail-closed gate blocks the batch; repair at the chokepoint
  (`clip_standard.repair_audio`), never re-render by hand. Detail: archive.
- **A step that lives only in shell history is not reproducible.** An unsaved
  ad-hoc mux shipped 939/1241 duplicate frames; the segments were fine.
- **Never decide on missing/stale data** (2026-11-12): a blank/stale newest row is
  `data`, never a guess; `--assert-fresh` gates the dashboard rail.
- **`videos.list` ≤50 ids/call; YPP = 1,000 subs AND 4,000 watch-hours.**
- **Bound every rail:** `timeout-minutes` + `cancel-in-progress: true`. Risks:
  `OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py --strict`.

## Dreamina CLI — free-tier reality (measured 2026-11-19)
`/workspace/ax-tools/bin/dreamina-canvas`. Non-VIP: **image + TTS work; video is
BLOCKED server-side** on every model (quote error 1 / `state: UNKNOWN` / 40012,
0 cr) even when it says `vipRequired: false` — `node quote` is the only honest
test. 8 cr/image, 1 cr/TTS. **No Thai voice** → Thai stays `edge-tts`.

## Recovery
`$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (`axvault:readme`); a lost `work/*.json`
is in the event log.
