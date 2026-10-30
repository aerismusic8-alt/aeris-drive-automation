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

## อำนาจและขอบเขตของ AR (K, 2026-10-30)

- **K มอบหมายให้ AR ปั้นช่องเอง** — AR มีอำนาจตัดสินใจเต็มในงานนี้: เลือกกลยุทธ์,
  เลือกเครื่องมือ, จัดตารางปล่อยงาน ได้เองโดยไม่ต้องขออนุมัติทีละขั้น.
- **เงื่อนไขเดียว: ฟรี** (กฎข้อ 1 ยังอยู่). ทุกเครื่องมือต้อง 0 บาท.
- **เป้าผลงาน: คุณภาพระดับมีคนติดตาม** ไม่ใช่แค่ปล่อยให้ครบจำนวน.
- K ยังคงเป็นผู้บริหารสูงสุด; AR รายงานเป็น PCSEV.

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

- **Measured 2026-10-30:** `UCm44BjAn03ruOF-WaA3ZRww`, **0 subs, 8 videos, 442 views,
  11m19s runtime**, lang th. Existing work is Shorts-shaped around one artist `NAVIYA`.
  The ch3 token carries scope `.../auth/youtube` (full) — upload verified working.
- **Bar (Google, 2026-10-30): 1,000 subs AND 4,000 watch hours / 12 mo**, or 1,000 subs
  AND 10M Shorts views / 90 days. Gap is ~everything. Free path = long-form volume;
  Shorts-only would need 10M views. **A 60-min compilation earns 1 h per view vs 3 min
  for a song — the main lever** (`scripts/compile_album.py`).
- **YouTube API quota: 10,000 units/day, 1,600 per upload → ~6 uploads/day.**
  `scripts/release.py --plan` paces releases around it.
- **The rail is `ops/`** (`yt_auth.py whoami|videos`, `yt_publish.py`, `yt_branding.py`,
  `ax_channels.json` = the channel registry, `AX_CHANNELS.md` + `AX_CHANNEL_DOSSIERS.md`).
  It was **missing from this clone** and lived only in a sibling checkout plus the vault;
  restored and committed here (4a6457c). If it vanishes again: vault key `axvault:readme`,
  `ops/ax_vault.py`.
- **K's rules still bind:** K reviews a channel's first work; never rename a channel
  without K's approval.

## music938-1 — why the pack had 1 song of 20 (root causes, 2026-10-30)
Three faults stacked; each alone blocks the pack. All are fixed and guarded.
1. **Lyrics too short.** Song 01 = 39 sung lines; 02-20 were 22. Create is clamped
   near 180s, so a 22-line lyric can never fill the 3.5-min brief. `expand_lyrics.py`
   took all 20 to 39-40 lines; `flow_song.py --check` fails under 30 lines.
2. **One Extend is not enough.** Create caps at 3:00; the Extend panel adds a fixed
   ~60s (range read `2:28-3:28`), landing ~3:28 — still under 210s. `flow_song.py`
   now extends in a loop, splicing a returned tail or adopting a longer re-render,
   until the take clears the floor.
3. **A short take was trusted forever.** `built()`/`generate()` checked only that the
   mp3s existed, so song 01 (178.7s) was skipped on every run. Both now require
   `MIN_SECONDS` (210) and rebuild otherwise.
- **The Flow Music 429 is account-wide and time-windowed, not parallelism.** A single
  solo attempt 429s in the dead zone; the account's own newest clip was created
  18:53 UTC, inside the predicted window. Default `--workers 1`: a second create in
  flight only gets 429'd.
- **Thumbnails must be 16:9.** The 1280x1280 covers get pillarboxed; `covers.py`
  now also emits 1280x720 `library/thumbs/thumb-{kind}-{slug}.png`, which
  `release.py` prefers.
- **`lyrics_timing` is `not_requested`** on a fresh clip and needs a throttled
  producer call, so karaoke timing is estimated. The clip's own lyrics are saved to
  `clipmeta-<slug>.json` for a later word-accurate pass.
