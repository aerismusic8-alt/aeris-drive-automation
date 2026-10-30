# MEMORY — index

> Index only, and it must stay small enough that the harness injects **all** of it.
> The cap is ~6,000 characters. Detail goes to the daily logs, not here.
> The full pre-rewrite file is preserved in `MEMORY-ARCHIVE.md` (search it before
> re-deriving anything).

## Roles and method (K, 2026-10-30)

- **K = ผู้บริหารสูงสุด (Final Authority).** Every standing rule below is K's.
- **AR = me.** I administer all of K's work in K's place: I decide, execute and
  report; I do not wait to be told each step. When I must choose, I choose the
  option that satisfies K's rules, and I say what I chose and why.
- **Method: PCSEV, every task, deliberately — P**roblem, **C**ause, **S**olution,
  **E**xecute, **V**erify. State each step. Do not skip to Execute.

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only

Everything must be 100% free. A paid API, subscription or credit pack is not a
trade-off to weigh; it is out. Cancel it and never propose or compare it again.
Free routes only: login-only web apps driven through headful Chromium
(Gemini web, Flow Music), open APIs, self-hosted tooling.
**The agent must never type a password** — drive the browser the operator has
already signed into.

## music938-1 — where it stands (2026-10-30)

Thai karaoke pack: 20 songs, each with lyrics, a **real sung vocal**, a
true-instrumental karaoke mix, cover art and a 1920x1080 word-synced video.

- **Voice source is Flow Music (free, login-only), driven by its own API** —
  `POST /__api/producer/tool-call`. A TTS melody is **not** singing; the earlier
  Piper attempt failed and must not be revisited.
- **Create is capped at 180s and the cap is not model-gated** (the bundle clamps
  with `Math.min(180, …)`). Extend is therefore always required to reach 3.5–5 min.
- **The throttle is account-wide and intermittent, not a quota.** Windows open
  (~4.3 min/song on 2026-10-29). The window is the scarce resource, so the batch
  runs a 2-worker pool: `scripts/build_songs.py --workers 2`.
- Karaoke = sum the non-vocal stems, not centre-cancel. Timing markers exist only
  on the Lyria agent path, so the sweep is estimated by design.
- Run `scripts/watch.sh` for progress, `scripts/resume.sh` after a pod recycle.
- Still blocked on Flow Music's own availability. Full detail: `2026-10-29.md`.

## Environment facts that keep costing time

- **A pod recycle is the recurring failure, not quota.** It kills the cloud
  desktop, the running job, `$HOME`, `/tmp` and the pip packages. Only
  `/workspace` survives. Never keep state in `$HOME` or `/tmp`.
- **Chromium CDP dies after a recycle** on a stale `SingletonLock` that points at
  the dead pod. Clear `Singleton*`/`DevToolsActivePort` and relaunch; keep
  `--remote-allow-origins=*` or every CDP websocket 403s.
- **`~/.config/aeris/gh-app.pem` is gone** (it was on the overlay). The sandbox
  `GITHUB_TOKEN` is read-only; PC1's PAT is the write path.
- **Roblox:** `multiget-playability-status` reports the *caller*, not the game —
  always probe with a control. `BUILD_REF` lies; the built tree comes from the
  `ax-arena-roblox-game` branch.
- Do not trust a URL: confirm the path exists in the provider's own spec before
  blaming a credential.

## Recovery

- Sandbox died? Read `ops/AX_RECOVER.md` first — do not re-learn it.
- Durable knowledge vault: `$AX_VAULT_BOOTSTRAP` -> `ops/ax_vault.py`, read KV key
  `axvault:readme` first.
- Full detail for anything above: `MEMORY-ARCHIVE.md` and the daily logs.

## ch3 AERIS Music — the revenue goal (K, 2026-10-30)

**K's directive:** make `@aerismusicth` a record-label channel with a real following,
publishing only high-quality work, and **first pass YouTube's monetization threshold**.
`aerismusic8@gmail.com` may be used for any tool AR needs.

- **Measured 2026-10-30:** channel `UCm44BjAn03ruOF-WaA3ZRww`, title `AERIS Music`,
  **0 subs, 8 videos, 442 views, 11m19s total runtime**, defaultLanguage th / country TH.
  Existing work is Shorts-shaped (7 of 8 under a minute) around one artist `NAVIYA`.
- **The ch3 token carries scope `.../auth/youtube` (full) — upload works.** Verified.
- **Monetization bar (Google, read 2026-10-30): 1,000 subscribers AND 4,000 qualified
  watch hours in 12 months**, or 1,000 subs AND 10M qualified Shorts views in 90 days.
  At 11m19s of catalogue and 442 lifetime views the gap is ~everything. The only free
  path is volume of real, watchable long-form; a Shorts-only strategy needs 10M views.
- **The rail is `ops/`** (`yt_auth.py whoami|videos`, `yt_publish.py`, `yt_branding.py`,
  `ax_channels.json` = the channel registry, `AX_CHANNELS.md` + `AX_CHANNEL_DOSSIERS.md`).
  It was **missing from this clone** and lived only in a sibling checkout plus the vault;
  restored and committed here (4a6457c). If it vanishes again: vault key `axvault:readme`,
  `ops/ax_vault.py`.
- **K's standing rules still bind:** upload only when K says so; K reviews each channel's
  first work; never rename a channel without K's explicit approval.
