# Competitor research — Thai music long-form (real scan, 2026-11-15)

Read with **eyes and ears on real channels**, not an assumption: `ops/yt_public_scan.py`
reads public channel pages (`ytInitialData`) — no YouTube API quota, no login. Raw
data: `thai-music-channels.json`, `thai-music-vol-series.json` in this folder.

## What the winners actually look like

Scanned "เพลงไทย เพราะๆ ฟังสบาย" and "รวมเพลงไทยใหม่ ฟังยาว" (top channels):

| channel | subs | median views | shorts | long-form |
|---|---:|---:|---:|---:|
| 365 เพลงเพราะๆ ฟังสบาย | 1,580 | **3,200** | 0 | 30 |
| 24.7 เพลงเพราะๆ ฟังสบาย | 3,390 | **3,700** | 5 | 30 |
| RSM เพลงเพราะฟังสบาย | 6,080 | 388 | 37 | 30 |
| รวมเพลงฟังสบาย ไม่มีโฆษณา | 152,000 | **22,000** | 5 | 30 |
| รวมเพลงใต้เพื่อชีวิต | 5,540 | 1,600 | 0 | 30 |
| GMM สบาย สบาย (label) | 96,300 | 440 | 48 | 30 |
| 🌙 เพลงไทยเพราะๆ ฟังสบาย (dead) | — | **1** | 0 | 15 |

The winning shape, verbatim from their titles:

```
🎵 เพลงเพราะๆ ฟังสบาย Vol.152 | รวมเพลงใหม่ ฟังยาว ไม่มีสะดุด เปิดฟังทั้งวัน
```

- **100% long-form continuous compilations**, ~73-80 minutes each.
- Published as a **numbered series** — the leader is at Vol.160+, a channel with
  only 100 subs is at Vol.57. The number is the promise of "next episode".
- Channels that post *mostly Shorts* are either big labels (GMM, 96k subs) or
  dead (median 1 view).

## What this says about us

Our channel (`@aerismusicth`) ships a themed album **once per theme** (sad /
chill / power) and then the rail no-ops. There is no Vol.2, so YouTube has no
"next episode" to suggest and Studio Analytics shows **0% returning viewers**
(99% new; Browse 53% + Suggested 33% already do the discovery). The missing piece
is a reason to come back — exactly what the numbered series is.

## Decision (advisor panel, quorum PASS)

`ops/consult.py` — duck + pollinations, both chose **(A) publish a numbered
weekly long-form Volume Series** over reworking Shorts:

- duck: "make each volume a genuinely continuous ~75-minute session, strongest
  songs up front, rotating the 28-song catalog."
- pollinations: "a 'next volume' breadcrumb so a finisher is pointed at Vol.N+1."

## What shipped (PCSEV)

`music938-1/scripts/volume_series.py` — builds Vol.N: newest songs lead, the
catalogue rotates by volume so consecutive volumes differ, one continuous mix,
title `🎵 เพลงเพราะๆ ฟังสบาย Vol.N | รวมเพลงใหม่ ฟังยาว ไม่มีสะดุด เปิดฟังทั้งวัน
(เลือกเพลงฟังได้)`, description with chapters + subscribe + Shopee + "ตอนถัดไป:
Vol.N+1". Wired into `ax-music-compilation.yml` (weekly) with `upload_compilation.py
--series-volume`, so the number only advances after a real upload succeeds.
