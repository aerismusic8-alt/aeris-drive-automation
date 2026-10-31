# music938-1 — the plan to make AERIS Music a real channel

Owner: AR (full authority, K's standing delegation 2026-10-30). Budget: **0 baht,
forever** (K's Rule #1). Every tool below is free.

## The goal, in numbers

YouTube monetization needs **1,000 subscribers AND 4,000 qualified watch hours in
12 months** (or 1,000 subs and 10M Shorts views in 90 days). The channel today is
0 subs, 8 videos, 11m19s of catalogue, 449 lifetime views.

## Discovery first — the channel's own numbers say so

Measured 2026-10-30, per video:

| video | views |
|---|---|
| Short (22s), 2026-08 | **234** |
| Short (23s), 2026-08 | **126** |
| long-form visualizer (3m) | 32 |
| Short (48s), 2026-08 | 22 |
| Short (57s), 2026-10 | 20 |
| Short (57s), 2026-10 | 8 |
| long-form (4m), 2026-10 | **1** |

**382 of 449 views came from Shorts. Long-form got ~33.** A channel with no
subscribers gets no long-form impressions — YouTube gives Shorts free
distribution and long-form almost nothing until an audience exists. So the plan
has two stages, in this order:

1. **Discovery (now):** a Short per song. Vertical, chorus hook, big Thai
   captions. Free reach. This is the only thing that has ever moved this channel.
2. **Watch hours (once there is an audience):** the long-form songs, karaoke and
   compilations. These are what earn the 4,000 hours, but they need someone
   watching first.

A Short is under 60s, so it does **not** wait on the 3.5-minute floor that gates
the songs. The rail runs today, on song 01, while generation is still throttled.

## What 43 competitor channels say (measured 2026-10-30)

Full write-up and method: `COMPETITOR-ANALYSIS.md`. Raw data: `work/competitors.json`
(43 channels, 1,546 videos, 885 API units). Re-run with `scripts/competitor_scan.py`.
This is not a style opinion — it is what the channels that already win these search
terms actually do.

**1. Long compilations get more views and vastly more watch time.**

| format | n | median views | p75 | p90 |
|---|---|---|---|---|
| Short ≤60s | 65 | 1,300 | 10,803 | 55,027 |
| Song 1–5 min | 742 | 1,410 | 8,582 | 56,184 |
| **Compilation ≥30 min** | **573** | **3,578** | **17,276** | **126,372** |

**2. `เลือกเพลงฟังได้` is the strongest single signal in the dataset.** 37 videos
past 100k views carry the phrase; **zero** of the sub-1k videos do. It is a promise
that the long file can be skipped around in — which is only true if the
description carries chapter timestamps. Both the title phrase and the chapters are
now built by `compile_album.py`, and a 12-track floor stops a thin one shipping.

**3. Winner titles are shorter and use `|` far less.** Past 100k: 47.9 chars, `|`
in 8% of titles. Under 1k: 60.7 chars, `|` in 38.9%. YouTube truncates past ~60
characters, so a long title hides its own tail. Every `| AERIS Music` suffix was
removed from the Short and karaoke titles.

**4. Our thumbnails were measurably flat.** Luminance standard deviation: the top
12 competitor thumbnails span **21.7–80.1**; ours measured **13.4–23.9**. Raising
the palette brightness did not move it — the frame stayed flat, just lighter. A
light source (`_highlight`), a deeper vignette and a dark title band
(`_text_band`) now put every cover and thumbnail at **41–58**. `covers.py` and the
test suite pin this.

**5. Active channels ship ~4 uploads/week.** Three of the top channels upload at
3.89/week — the quota ceiling. We are at 1.01/week, gated by how many songs exist,
not by release discipline.

## The arithmetic that decides the release shape

- One 3-minute song watched once = **0.05 h**. Songs alone would need ~80,000 views.
- One 60-minute compilation watched once = **1.0 h**. It would need ~4,000 views.
- Same songs. Same generation cost. **20x less audience for the same hours.**

So each song is released as three videos from one generation:

1. a **Short** — the chorus hook, for discovery
2. the **song** — the main long-form release
3. the **karaoke** — the sing-along long-form

and every ~10 songs become one **compilation** — the watch-hour lever, once the
Shorts have built an audience for it.

## What is free and what it costs

| need | tool | limit |
|---|---|---|
| song generation | Flow Music (login-only web app, headful Chromium) | server-side throttle, not quota — see below |
| covers | PIL in `scripts/covers.py` | none |
| video (song + karaoke) | ffmpeg | none |
| compilations | ffmpeg acrossfade | none |
| upload | YouTube Data API | **10,000 units/day, 1,600 per upload → ~6 uploads/day** |
| playlists | YouTube Data API | 50 units each |

AiPASS was considered as a second song source. It gives **10 tracks/month**, which
is one artist's release and far too thin for 20 songs, and it needs the PC1
desktop. Flow Music is the better source and is already wired.

## The Flow Music throttle is a window, not a wall

Every generation tool returns `429 {"detail":"Too Many Requests"}` and the UI
Generate does too. It is not quota — credits read 6,000 tokens / 500 credits
while every call 429s.

The account's own clip history (`GET /__api/clips/auth-user`) shows the shape.
Of 33 clips over four days, **every successful `create_song` landed in UTC hours
23, 0, 1, 2, 6 and 18**, and **07:00–17:00 UTC has zero successes**. Inside a
window, one 26-minute span rendered 6 songs (~4.3 min/song).

`scripts/build_songs.py` now encodes this: probe every 60s inside a likely
window, and outside one nap toward the next window (capped at 900s). Hammering
the dead zone only burns the retry ladder.

## Cadence

- Generation runs on the windows; it cannot be forced and does not need to be.
- **Release at most 6 uploads/day**, spread across the day, not dumped at once.
- **Lead with Shorts.** `release.py --plan` puts the Short first, then the song
  and karaoke, so discovery comes before the watch-hour videos.
- The first upload of the pack stays **private for K** to approve. `--public` is
  a deliberate opt-in, never a default.
- **Target ~4 uploads/week once the catalogue supports it.** The scan measured
  three of the largest Thai music channels at 3.89/week — the practical quota
  ceiling. We are at 1.01/week today; the limit is how many songs exist, not the
  release schedule.
- One new compilation per ~12 songs, so a compilation is never thin. The title
  says `N เพลง`, so a 1-song "compilation" would be a lie.

## Commands

```bash
# generate (window-aware; run it and leave it)
python3 scripts/build_songs.py

# a Short from any song already on disk (runs even while throttled)
python3 scripts/make_short.py 01-khon-di-thi-chak-pai
python3 scripts/make_short.py --all

# what would be released, and when (Shorts first)
python3 scripts/release.py --plan --days 7
python3 scripts/release.py --plan --shorts        # the discovery queue only

# release the next item (private for K; add --public to publish)
python3 scripts/release.py --next

# build a 60-minute compilation from what is on disk
# (writes the title and the chapter list; refuses under 12 tracks)
python3 scripts/compile_album.py --name "รวมเพลงไทยเพื่อชีวิต" --max 60 --render

# re-read the competition and refresh the evidence
python3 scripts/competitor_scan.py --queries-file competitor-queries.txt \
    --per-query 6 --videos 40 --out work/competitors.json
```

## Known gaps, stated plainly

- **11 of 20 songs are not generated yet (09 built, 10-20 missing).** Generation
  runs on Flow Music, which needs the operator's Google session in the cloud
  desktop. That session **expires whenever the pod recycles** — the login cookie
  is the only thing that does not survive, even though the profile dir is on
  `/workspace`. When it is signed out (`check_login.py` -> `RESULT=SIGNED_OUT`)
  the batch cannot generate, no matter how open the throttle window is. K signs
  in once via noVNC; then the batch resumes on its own.
- **The Flow Music 429 throttle is real and account-wide**, independent of the
  login. Even signed in, generation only succeeds inside a window (UTC 23,0,1,2,6,18).
- **Karaoke subtitles are estimated**, not from real lyric timing. Flow Music
  does expose `lyrics_timing` on a clip; wiring it in would make the karaoke
  word-accurate. That is the next quality upgrade.

## Current state (2026-10-31 14:30 UTC)

- **Built and stored (as `media-938` release assets): songs 01-09** — song mp3 +
  karaoke mp3 + song video + karaoke video + three Shorts each, plus covers and
  thumbnails. 150 assets, 529 MB. `library/` is gitignored; the release is the
  durable copy, so a fresh pod restores it with `scripts/pull_media.py`.
- **Live on ch3 (@aerismusicth): 15 videos.** Song 01 (song `ASuxGEvJBlw`,
  karaoke `SWS1vJJgkow`, three Shorts) and song 02 (song `SZO66B-RIIQ`, karaoke
  `ohmKsjI5Sq8`, three Shorts) are public; song 03's first Short `51EuOXD3HPA` is
  public and the rest of song 03 is scheduled.
- **Release queue: 34 items pending** (the rest of 03 through 09), 6/day.
- **Today's YouTube quota (Pacific day) is spent: 6/6**, by the 07:01Z batch. The
  next batch is the `AX Music Daily Release` automation at 07:05Z tomorrow.
- **`AX Music Daily Release` was re-enabled today** after the platform auto-paused
  it (5 consecutive failed runs, all cold-start flakes — `Sandbox not available` /
  `agent_server fetch_plugin timed out`, not our code).

## Why only song 01 existed, and what was actually wrong

Three separate faults stacked up, and only the last was visible:

1. **Lyrics were too short.** Song 01 has the full form (verse 8 / chorus 8 /
   verse 4 / chorus 8 / bridge 3 / chorus 8 = 39 lines). Songs 02-20 were written
   at half that (22 lines). `expand_lyrics.py` gives all 20 the full form.
2. **One Extend is not enough.** Create is clamped to 3:00 and the Extend panel
   adds a fixed ~60s step (it showed a `2:28-3:28` range), so a single extend
   lands near 3:28 — under the 3.5-minute floor. The generator now extends in a
   loop until the take clears the floor.
3. **A short take was trusted forever.** `built()` only checked that the two mp3s
   existed, so song 01 (178.7s) was skipped on every run and could never be
   rebuilt. It now also requires the floor.

Song 01 is being regenerated. Its 178.7s take was the model's create ceiling plus
one extend, not a finished song.
