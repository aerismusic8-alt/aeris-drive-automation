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
