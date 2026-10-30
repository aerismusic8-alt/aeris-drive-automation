# MEMORY — index

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

- **Voice source is Flow Music (free, login-only)**, driven through the
  signed-in Chromium. A TTS melody is **not** singing; the Piper attempt failed.
- **The 429 is account-wide and time-windowed, not parallelism.** A solo attempt
  still 429s in the dead zone. Run `--workers 1` — a second create in flight only
  gets 429'd. Windows: UTC hours 23,0,1,2,6,18; dead zone 07-17. Verified 2026-10-30:
  every probe 14Z and 15Z 429'd. **Queue a song with no take before a rebuild**
  (`build_songs.pending.sort`), or a rare window just re-cuts a song already held.
- **Extend has never produced a single clip.** Read the account's own history:
  `GET /__api/clips/auth-user` (Supabase bearer captured off any `/__api/` request)
  shows 16 `audio__create_song` clips at 160-181s and **0 extends, ever**, so the
  3.5-min floor never rested on anything real. A live Extend Generate returned the
  same 429 as create — Extend is throttled too, not broken. `CREATE_LENGTH` now
  asks `4:30` (env `FLOW_CREATE_LENGTH`); whether the Length seed can exceed 3:00
  is still unverified. Extend stays a best-effort fallback.
- Karaoke = sum the non-vocal stems, not centre-cancel. `lyrics_timing` is
  `not_requested` on a fresh clip, so the sweep is estimated by design.
- Run `scripts/watch.sh` for progress, `scripts/resume.sh` after a pod recycle.
- **Why only 1 of 20 songs existed** — three stacked faults, now fixed and
  guarded: (1) lyrics 02-20 were half-length (22 vs 39 lines) so they could never
  fill 180s → `expand_lyrics.py` (all 20 now carry 39-40 sung lines, re-checked);
  (2) one Extend left takes under the floor → extend loop in `flow_song.py`, but
  no extend has ever succeeded, so this is still the open fault; (3) `built()`/
  `generate()` trusted any existing mp3, so the short song 01 was skipped forever
  → both now require 210s.
- Full detail: `2026-10-29.md`, `2026-10-30.md`.

### The clips render text now — two silent failures, both fixed

K: "ตัวหนังสือในคลิปอ่านไม่ออก ภาษาอะไร ภาพพืนหลังไม่มี". Both were real, and both
played fine, so nothing downstream ever failed.

- **Tofu text.** Every ASS style names `Noto Sans Thai` and the image ships **no
  Thai font** (`fc-list :charset=0e01` is empty). libass substitutes a Latin face
  and draws one box per syllable. `covers.py` failed the same way from the other
  side: it pointed at a `NotoSansThai-Regular.ttf` that does not exist and its
  `except OSError` fell back to Pillow's bitmap default, which has no Thai either.
  Fix: font bundled at `music938-1/fonts/NotoSansThai.ttf` (variable font —
  `set_variation_by_name("Bold")`, no second file), fetched by
  `scripts/install-thai-font.sh`. **libass needs `fontsdir=`**; naming the family
  is not enough. Both paths now raise on a missing font. `test_thai_font` guards it.
- **Near-black frames.** `PALETTES` was tuned on a bright monitor and then a 0.52
  vignette stacked on top: covers measured lum 47/255, std 11.7 — hence "no
  background". Raised the anchors, vignette 0.28, and the Shorts chain no longer
  adds another `-0.22`. Now 98/255, std 25.5.
- **YouTube cannot swap a file under an id.** A bad clip is upload-then-delete, in
  that order. `scripts/replace_video.py` does the whole job: new id, playlist
  re-add, **playlist placeholder removal** (a delete leaves a `Deleted video`), and
  an **appended** ledger row so `uploads_today()` still sees the spent slot. A
  DELETE must carry no body. Song 01: `oliw1meKfcQ` → `ASuxGEvJBlw`.
- **6 uploads per Pacific day** (reset 07:00 UTC), so a broken batch waits for the
  next day. Still-broken ids are in `work/pending-replacements.json` (un-ignored).

**HOLD LIFTED 2026-10-30** — K: "อนุมัติ ดำเนินการแทน K", AR acts on K's behalf.
Song 01 is live on @aerismusicth: full song `ASuxGEvJBlw` (2:59 public), karaoke
`SWS1vJJgkow`, three hook Shorts `ANwgi7J_ras`/`JId5J48t4a4`/`CXRH7sW6Gcw`
(playlist `PLKlARHtRpKkI`). `release.py --next` uploads **private by default**
(needs `--public`) and records `public: false` even after a later `videos.update`
makes it public — correct the ledger by hand. `work/release-state.json` is tracked:
it is the only record of what is already up, and a clone that loses it re-uploads
duplicates. Probing is **all-hours** (K freed the timing): `PROBE_SLEEP_S`=150s, no
dead-zone gate. The one red test is real: song 01 is 178.7s vs the 210s floor.
(The five Piper-dependent checks now skip loudly via `voice_ready()`; Piper belongs
to the *retired* pipeline and is absent, so `is_speakable` was False for `ดี` and
`ไป` alike. When every item in a check fails, suspect the checker's dependency.)

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
