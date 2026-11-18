# MEMORY — index

**How to use.** Injected every session; **capped at 6 KB** by `ops/memory_guard.py`.
Rules/pointers only — detail in `MEMORY-ARCHIVE.md` + daily logs. New learning →
today's log; promote only if it changes a decision; **move** superseded detail to
the archive. **Read `.openhands/CHARTER.md` first** — K's mandate (2026-10-31).

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only
100% free: no paid API, subscription or credits. Free routes only — login-only web
apps (K's Chromium), open APIs, self-hosted tooling. **AR never types a password.**
Related: **AUDIO FIRST**; delete the duplicate and the worthless, never archive it;
K reviews a channel's first work; never rename a channel without K's approval.

## Accounts (K, 2026-11-14): every tool uses AR's OWN mail, not K's
AR mailbox = `araeris4770d7@fldubai.com` (mail.tm; `ops/ar_identity.py`).
AR self-creatable: **Nostr** (`AR_NOSTR_NSEC`), **Telegraph** (`ops/ar_telegraph.py`).
Flow Music/Gemini = K's account `aerismusic8` (AR never types a password). K taps a
QR once, then `login_vault.py save` **immediately** — the session lasts ~1 day. A
synth bed has **no vocal**; Flow is the only real-song route (K: "ยากแค่ทำเพลง").

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
- **MV links must be durable (K: "ลิงค์ตาย").** GitHub Pages `ax-mv-pages`
  (`ops/mv_page.py --all`); a /tmp preview dies on recycle.
- **24/7 runs on GitHub Actions** (public repo → free minutes); judge health from
  the **rail run history**, not `heartbeat.json`.
- **FB = Graph API only (K 2026-11-15); browser OFF.** `api-only`; vault
  `axsecrets:fb-page-token`; lanes in `crosspost.py`.
- **Vault = source of truth; a secret injects only when the command *names* it**
  (`AX_VAULT_BOOTSTRAP`/`OPENHANDS_API_KEY`).
- **Writes:** `GITHUB_TOKEN` is 403; push via KV `axsecrets:gh-workflow-token`
  (workflow files need its `workflow` scope).
- **Desktop = Live View** (`work-2`:12001); Thai text `Text.luau` +
  `NotoSansThai.ttf` (else tofu); burned ASS has no emoji.
- **Playwright `connect_over_cdp` can hang** though CDP answers: kill
  `remote-debugging-port=9222`, re-run `bootstrap.py`; raw CDP websocket works.
- **`ops/websearch.py`** is the free web search (Tavily has no quota left).

## Sound + clip quality (K)
**sfizz** sampler, not GM; `AX_REQUIRE_REAL_INSTRUMENTS=1` → a fallback **raises**.
**One FLOOR, every format/channel (2026-11-17): "ห้ามอัพขึ้นเด็ดขาด".**
`ops/clip_standard.py` = floor + a per-format profile, gated at **every** upload
route, no override; `ops/thumb_standard.py` too. `docs/clip-standard.md`.

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
- **A derived artifact outlives its source.** Re-mastering a song leaves older
  rendered clips clipped; the fail-closed gate then blocks the whole batch (release
  red 3 runs). Repair at the chokepoint (`clip_standard.needs_audio_repair`/
  `repair_audio`, before the gate in `yt_publish.py`) — never re-render by hand.
- **A free drafter's content filter judges the *framing*, not the content** — a
  positive clause clears it; a committed manifest can desync from pulled media.
- **Never decide on missing/stale data** (2026-11-12): a blank/stale newest row is
  `data`, never a guess; `--assert-fresh` gates the dashboard rail.
- **`videos.list` ≤50 ids/call; YPP = 1,000 subs AND 4,000 watch-hours.**
- **Bound every rail:** `timeout-minutes` (default 360) + `cancel-in-progress:
  true`, or a hung step holds the slot. Risks:
  `AKATH_CORE/OPENHANDS_RISK_REGISTER.json` + `ops/risk_audit.py` (`--strict`).

## Recovery
Lost rail/file: `$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py` (`axvault:readme`) or
`MEMORY-ARCHIVE.md`; a lost `work/*.json` is in the event log.
