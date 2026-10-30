# AX 4-channel plan — K's confirmed direction

**This is the single entry point for channel work.** When the task is about creating or
updating a channel, open this table first. It carries the direction, the goal, the format
and the clip-making recipe for each channel.

Confirmed by K on 2026-10-24. Account: **`aerismusic8@gmail.com`** (this OpenHands account
owns the 4 automations and all 4 YouTube tokens). Budget **0 THB**, free generative AI only.

> **STATUS 2026-10-26 — ALL WORK SUSPENDED.** K paused everything. All 6 automations are
> `enabled=false` / `INACTIVE`; nothing is scheduled to run. Do not start a render, an
> upload, or an automation until K lifts the hold. See "The hold" below.

## The table

| ch | handle | channel id | direction | goal | runtime | status (measured 2026-10-26) |
|---|---|---|---|---|---|---|
| **ch1** | `@tatagenxgeny` | `UCI6EfsgM1HNjrYarvigxyrQ` | **ช่องปรัชญา** — life philosophy | a daily philosophy talk that people keep listening to | ~11 min | 28 vids, 6 subs · **1 duplicate title** |
| **ch2** | `@farmmer-n9t` | `UCM3QO5L_pmj34n1JVlbhh-w` | **ช่องธรรมะก่อนนอน** — dhamma before sleep | fall asleep to it, come back every night | 10–12 min | 3 uploads (2 public, 1 private), 1 sub |
| **ch3** | `@aerismusicth` | `UCm44BjAn03ruOF-WaA3ZRww` | **ช่องสร้างศิลปินเพลง** — build a music artist | one artist per month, 10 songs, real chart direction | 1 song 3 min | 4 vids, 0 subs, 413 views |
| **ch4** | `@kongkeatpratumma` | `UC7gCIu4G_7QCEJ8hJ-34zoQ` | **ช่องละคร · การ์ตูนอะนิเมะ** — drama and anime cartoon | an episodic drama / anime series people follow | 10–25 min | 5 vids, 0 subs · **1 duplicate title** |

Handles above are read live from the YouTube API, not copied from an old note. ch4's
handle **does** exist (`@kongkeatpratumma`); an earlier note wrongly recorded it as null.

**The channels moved under this note.** Between 2026-10-25 and 2026-10-26, while the
automations were failing, uploads landed on ch1, ch2 and ch4 that AX did not make — ch4
went from empty to 5 public videos. So any count in this file is only as fresh as the
timestamp beside it; re-read it from the API before quoting it.

**Duplicates to clean once work resumes** (K's directive 2: delete duplicates and
low-quality videos — do **not** delete anything while the hold is on):

| ch | title | what is wrong |
|---|---|---|
| ch1 | `5 ของใช้ในบ้านที่คุ้มเกินราคา สำหรับคนวั…` | two entries — one `private`, one `public` |
| ch4 | `เรื่องเล่าสั้น: ไผ่ที่รอสี่ปี` | two entries, both `public`, uploaded 1 min apart |


The deliverable is the **agent**, not a hand-built channel. K: "เราไม่ได้เป็นคนสร้างช่อง
เราสร้าง ai opendhand นี่คือเป้าหมายของ k".

## The hold (2026-10-26)

K: "ตอนนี้ระงับงานทั้งหมดไว้ก่อน หยุดงานออโต้ด้วย". What that means in practice:

- **No uploads.** ch2's first work is rendered and waiting; it stays private on disk.
- **No renders** started for ch1/ch3/ch4.
- **No automation enabled.** The 6 that exist are all off:

| automation | id | schedule (UTC) | why it is off |
|---|---|---|---|
| AX 4Ch Farmer — ตาต้า GenX Shop | `c5dc94de-…` | `0 1 * * *` | manual |
| AX 4Ch Farmer — Farmmer (ธรรมะก่อนนอน) | `9dd39ced-…` | `30 13 * * *` | auto-paused: 5 runs failed, none succeeded in 24 h |
| AX 4Ch Farmer — AERIS Music | `119f290e-…` | `0 4 * * *` | manual |
| AX 4Ch Farmer — kongkeat pratumma | `5a1ccd35-…` | `30 14 * * *` | manual |
| AX Content Lab - Daily Production Loop | `09bb7104-…` | `0 7 * * *` | manual |
| AX KNOWLEDGE VAULT (do not delete) | *(anchor)* | `0 0 1 1 *` | off by design — never runs, never costs a token |

Manage them at `https://app.all-hands.dev/api/automation/v1` (Bearer `OPENHANDS_API_KEY`).
The v1 app API does **not** expose automations — the base is `/api/automation/v1`.

## The rule that governs every channel: AUDIO FIRST

K: "การที่จะทำให้คนเล่นคลิปของเราและเล่นได้นานๆจนจบคือเสียง ... เหมือนสมัยก่อนแค่เปิดวิทยุ
ฟังเสียงดีเจ เฉยๆทั้งวันก็ยังได้เลย"

Retention is won by the sound. The narration is the product; pictures are support.
Build and measure the **audio bed first**, then lay stills on top.
**The music bed must never be louder than the voice, even during pauses.**
Target **-17 LUFS integrated, true peak ≤ -1 dBFS**, mix tracks the voice within ~+0.3 dB,
pauses 5–6 dB down.

## K's review rule for first work (stated 2026-10-26)

Every channel's **first** episode goes to K before it is uploaded. Nothing is published
until K approves. Once a channel's first work passes, that episode becomes the channel's
template and an automation is created for it. Per-channel state lives in
`ops/ax_channels.json` under `channels.<ch>.first_work`.


---

## ch1 — ช่องปรัชญา (life philosophy)

**Goal.** A philosophy talk in Thai, long enough to live inside, warm and plain-spoken.
The catalogue already proves the format works: 76 videos, the dominant series is
"ปรัชญาชีวิต" at ~11 min each.

**Clip-making.** Stills + Thai narration + music bed. Same rail as ch2 (see below) but with
philosophy stills — open skies, roads, hands, coffee, rain — not temple imagery.

**Naming.** The handle `@tatagenxgeny` and the name "ตาต้า GenX Shop" say *shop*, while the
catalogue is philosophy. A rename is prepared in `channel_branding.json` but **must not be
applied without K's explicit approval** — a display name is hard to undo once seen.

## ch2 — ช่องธรรมะก่อนนอน (dhamma before sleep)

**Goal.** Someone presses play in bed and is asleep before the end. Calm, slow, no sudden
changes. The whole catalogue is already this: 11 videos, all "ธรรมะก่อนนอน", 10–12 min.

**Clip-making.** The reference implementation of the rail. The modules below are libraries
with no CLI, so drive them with **`ops/ax_make_episode.py`** (written 2026-10-26), which
runs the steps in this order and can be re-run per step with `--only audio|video|meta`.

1. Write the Thai script into `scripts_th/*.md`, one paragraph per TTS call, with a
   `# TITLE:` line. Size it at **13.6 Thai chars/s at rate=-8%** — 9,365 chars → 12:35.
2. Narrate with `ops/thai_tts.py`, voice **`th-TH-NiwatNeural`** (male). Premwadee
   (female) throws `NoAudioReceived` often, so retry is mandatory either way.
3. Build the bed with `ops/audio_bed.py` — concat narration, `loudnorm`, loop the music
   with a crossfade, sidechain-duck it under the voice. **Bed gain 0.34**, not 0.9.
4. Prove it with `ops/ax_audio_qc.py --duck` before adding any picture.
5. Harvest stills with `ops/stills_rail.py` — Wikimedia Commons, **English queries only**
   (Thai returns 0 pages), keep CC0/PD/CC BY/BY-SA, **exclude NC and ND**, emit attribution.
   A checked pool already exists at `stock/<theme>/`; `ops/stock_kit.py verify` guards it.
6. Assemble with `ops/video_build.py`, metadata with `ops/episode_meta.py`.
7. **Standardise the audio after the final mux.** `video_build` writes **mono 96 kHz**;
   YouTube wants stereo 48 kHz. One pass:
   `-af "pan=stereo|c0=c0|c1=c0,loudnorm=I=-17:TP=-1.5:LRA=11,aresample=48000"`.
   `aresample` must come **last**, or loudnorm drags it back to 96 kHz, and dual-mono adds
   ~3 dB, so the same pass must re-normalise.

**Known state (re-measured 2026-10-26).** The branding drift is fixed: `defaultLanguage`
is now `th`, `country` `TH`, and the keywords are Thai. The old
`lanternwild kids cartoon animal stories kids songs` leftovers are gone. Verified by
reading the channel back from the API, not from a note.

## ch3 — ช่องสร้างศิลปินเพลง (build a music artist)

**Goal.** Build a named artist and release a real body of work, one artist per month. The
live channel already does this: 4 videos, "NAVIYA — FIRST LIGHT", best one at 232 views.

**The hard limit that shapes everything.** AiPASS gives **music 10 tracks per MONTH**. Ten
tracks is exactly one artist's release, so the cadence is **one artist per month**, not more.
Lyria 3 Clip on AiPASS has produced both a 30 s clip and a full **3:03 song**, 44.1 kHz
stereo — measured, so a full track is achievable.

**Clip-making.** Music first, then the visual.
1. Pick the artist concept and the chart direction for the month.
2. Generate the tracks on AiPASS (`สร้างเพลง` / Lyria 3 Clip) — budget 10 for the month.
3. Master to match: **AiPASS music arrives at -12 to -14 LUFS**, louder than our -16; match
   the reference rather than forcing it down.
4. Visuals from AI stills + ffmpeg motion, with **AiPASS Seedance only for hero shots**
   (video is 10 clips/MONTH for the whole account — see the arithmetic below).
5. Release one song at a time, each with its own thumbnail and description.

## ch4 — ช่องละคร · การ์ตูนอะนิเมะ (drama and anime cartoon)

**Goal.** An episodic drama / anime series that people follow episode to episode. This
channel is **empty** — no videos. The handle and name exist (`@kongkeatpratumma`,
"kongkeat pratumma"), but that is the account holder's personal name, not a series brand.
The display name is still K's decision of 2026-10-24; do not rename without approval.

**The arithmetic that decides the method.** AiPASS **video is 10 clips/MONTH** at ~4.1 s
each → roughly **50 seconds of AI motion per month**. A 25-minute episode is ~1,500 seconds.
So:
- **Episode bodies are built from AI stills + ffmpeg motion**, never from AI video.
- **AI video is reserved for hero shots and title sequences** — the few seconds that must move.

**Clip-making.** Treat it as an anime: consistent character design first, then scenes.
1. Fix the character sheet (appearance, outfit, palette) so the character is recognisable
   across episodes — this is what makes it a *series* rather than unrelated clips.
2. Scene stills from Pollinations; keep the same style prompt and seed per character.
3. Motion from ffmpeg (Ken Burns, parallax), with the zoom step **derived from the segment
   length** — a fixed rate freezes (see the traps below).
4. Narration by edge-tts; if the drama needs multiple voices, alternate the two Thai voices
   and vary rate slightly.
5. Hero shots from AiPASS Seedance, placed at the episode open and the cliffhanger.
6. Assemble 10–25 min, then metadata and chapters from the real TTS durations.

---

## Shared rails and their measured limits

| need | tool | measured limit |
|---|---|---|
| image | Pollinations `flux` | ~1 per 45 s, capped 1024x576, 402 common — always have a fallback |
| stills fallback | Wikimedia Commons | English queries only; Thai → 0 pages |
| narration | edge-tts | 2 Thai voices only: `th-TH-NiwatNeural`, `th-TH-PremwadeeNeural` |
| music | AiPASS `สร้างเพลง` / Lyria 3 Clip | **10 / month** |
| video | AiPASS Seedance | **10 / month**, ~4.1 s each → ~50 s of motion per month |
| images (AiPASS) | Nano Banana 2 | **20 / day** |
| assemble | ffmpeg | 25-min episode verified 1920x1080 at -16.8 LUFS |
| our own music | CC0 tracks | `https://farmmer938-lgtm.github.io/aeris-store/free/tracks/<name>.mp3` |

**AiPASS quota is the binding constraint for ch3 and ch4, not quality.** It is free only for
signups between 19 Aug and 30 Nov 2026 and only while the course tasks keep the quota up —
temporary and conditional. Plan the month around it.

## Traps that cost real time (all reproduced)

- **`zoompan` with a fixed rate freezes.** `z=min(1+0.001*on,1.10)` hits its ceiling in ~4 s
  and holds a still for the rest of a 17 s segment — measured **747 of 1510 steps static**.
  Derive it: `step = zoom_span/frames`.
- **Never claim to have watched or heard anything.** Report measured numbers only.
- **Never reuse another channel's video files.** Ideas and free tools only.
- **Account rotation is forbidden.** Upload cap is per channel; a 403 quotaExceeded means
  that channel is capped for the day.
- **AX does not upload.** K reviews first; publish only when K says so.
- **Never assume a duration.** Measure it, then add or cut a story.
- **A 30 s shell cap kills long ffmpeg** — run detached and poll the log.
- **Pollinations Thai text is unusable** for narration. **AX writes the Thai scripts itself.**
- **`channels.update` replaces the parts you send** — send the COMPLETE
  `brandingSettings.channel` object or omitted fields are cleared.
- **`POST`/`PATCH` to `www.googleapis.com` return a bare 404** (sandbox proxy). GET and PUT
  reach the real API. Use PUT for resource updates.

## Per-channel automation

Each channel has a live OpenHands automation, all ACTIVE, all bound to its own channel key:

| automation | channel key | cron (UTC) | automation id |
|---|---|---|---|
| AX 4Ch Farmer — ตาต้า GenX Shop | `ch1` | `0 1 * * *` | `c5dc94de-ecd9-4615-9da1-2ddc4ed0adff` |
| AX 4Ch Farmer — Farmmer | `ch2` | `30 13 * * *` | `9dd39ced-9e92-4ac8-a422-cb1e071c94ba` |
| AX 4Ch Farmer — AERIS Music | `ch3` | `0 4 * * *` | `119f290e-b501-4eb4-82f9-95a65fb08709` |
| AX 4Ch Farmer — kongkeat pratumma | `ch4` | `30 14 * * *` | `5a1ccd35-f228-4021-8b63-b5e4e285fa9d` |

The four tarballs are byte-identical apart from `CHANNEL_KEY`. The rail inside is keyless
(Pollinations + edge-tts + ffmpeg), so a run costs **0 LLM tokens**.

## Scope

Four channels, four directions, one account, zero baht. Do not invent content for a channel
whose direction K has not confirmed — all four are now confirmed, so work may proceed on
whichever channel the task names.

Knowledge about how all of this was learned lives in `.openhands/memory/MEMORY.md` and is
kept durable in the AX knowledge vault — see `ops/AX_RECOVER.md`.
