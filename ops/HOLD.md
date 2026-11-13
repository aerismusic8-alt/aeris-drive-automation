# ⛔ WORK SUSPENDED — 2026-10-26, re-issued 2026-11-13

K (2026-11-13): "รอดูผลตอบรับเอามาวิเคราะห์และประเมิน คลิปที่ตั้งระบบอัตโนมัติไว้
ให้ระงับทั้งหมดก่อนนะ" — hold the automated clips, watch the response, then judge.

**Read this before doing anything on the 4 channels.**

## What is stopped (2026-11-13)

All 11 **publishing/rendering** GitHub Actions workflows are
`disabled_manually` (verified via `GET /actions/workflows`):

`ax-music-crosspost`, `ax-music-release`, `ax-music-compilation`,
`ax-music-admin`, `ax-music-dashboard`, `ax-music-produce`,
`ax-music-affiliate-render`, `ax-music-concert-render`,
`ax-music-karaoke-render`, `ax-music-surreal-render`, `ax-session-heal`.

All 12 OpenHands automations are `enabled=false` (the last one, *AX Music
Marketing Strategy (weekly)*, was turned off this day — it opened PRs, so it
belonged to the held set).

The read-only watchers stay ON, because the hold is *watch and judge*: the
feedback must keep arriving. `ax-rail-watchdog`, `ax-token-heartbeat`,
`ax-memory-guard`, `ax-risk-audit`, `ax-roblox-live-state`.

Re-enable with `PUT /actions/workflows/<id>/enable` and
`PATCH /automation/v1/<id> {"enabled": true}`.

## What must not happen until K lifts the hold

1. Do not enable any publishing automation.
2. Do not upload anything to YouTube / Facebook / TikTok.
3. Do not start a new render.

## Why it was re-issued: the response is the problem

Measured 2026-11-13 (see `work/response-review-2026-11-13.md`): the channel is
**not** under-performing because clips are missing; it is not finding an
audience at all.

- Whole channel: 72 uploads, **1,981 views total**, median **7.5 views**,
  15 likes, **1 comment**.
- Daily views collapsed: 847 (11-01) → 325 (11-10) → **0 (11-11)** → 10 (11-12)
  → 19 (11-13), while the posting rate went *up* (4–10 clips/day).
- Every genre label except the two "คิดถึง / เพื่อชีวิต" ones sits at 0–7 views.
  The rock pivot's song (`ยืนหยัดไม่ยอม`) is at **2 views**.
- 14 of 72 uploads have 0 views; 5 have ≥100, all of them older shorts.

Producing more clips does not fix this. The hold exists to stop the loop from
burning quota on output nobody watches.

## What survives the pause

| thing | where |
|---|---|
| ch2 first episode (233 MB, 12:35, 1080p) | `work/ep_ch2/ep_ch2_final.mp4` |
| ch2 metadata (title, 9 chapters, tags, credits) | `work/ep_ch2/ready/` |
| the Thai script | `scripts_th/ch2_ep_heart_rest_th.md` |
| the rail driver | `ops/ax_make_episode.py` |
| channel registry | `ops/ax_channels.json` |
| channel summary | `ops/AX_CHANNELS.md` |
| knowledge vault | `out/knowledge.tar.gz` |

`work/` is gitignored, so the rendered video is **not** in git. If the sandbox is
recycled, the mp4 is lost but the script and metadata remain — rebuild with
`python3 ops/ax_make_episode.py --ch ch2 --script scripts_th/ch2_ep_heart_rest_th.md
--work work/ep_ch2 --theme dhamma`.

## ⚠️ Unresolved: a clip with the same title is already live on ch2

Found 2026-10-26 by reading the channel, not from a note. ch2 currently holds:

| privacy | published | length | views | title |
|---|---|---|---|---|
| public | 2026-10-25 06:01 | **756 s** | 2 | `เหนื่อยทั้งวัน แค่อยากให้ใจได้พัก — ธรรมะก่อนนอน` |
| public | 2026-10-25 08:17 | 85 s | 1 | `ปล่อยวาง แล้วใจจะเบา` |
| private | 2026-10-25 02:13 | 649 s | 2 | `มัทนะพาธา ตำนานแห่งดอกกุหลาบ` |

The 756 s public video carries the **same title as the episode rendered here (755.5 s)**.
So either a near-identical episode was already published from another path, or this same
work was uploaded while the automations were failing. **AX did not upload it** — no upload
was run in this session, and the automations were all off.

Do not act on this unilaterally. Ask K:

1. Is the live 756 s video the approved first work for ch2?
2. If yes — is `work/ep_ch2/` a duplicate to discard, or a better version to replace it?
3. If no — the live video is unapproved and should be removed.

The same sweep found the channels moving under us: **ch4 went from 0 to 5 public videos**
between 2026-10-25 and 2026-10-26, and ch1 grew to 28. Duplicates to clean (K's directive
2) are listed in `AX_CHANNELS.md`.

## How to lift the hold

K says to resume. Then, in order:

1. `python3 ops/ax_setup.py` — a recycled pod loses ffmpeg and the python deps.
2. `python3 ops/ax_readiness.py` — expect `100% ready` before anything else.
3. ch2 is still awaiting K's review of its **first work**; upload only on approval.
4. Only after a channel's first work passes does it get a template and an automation.
