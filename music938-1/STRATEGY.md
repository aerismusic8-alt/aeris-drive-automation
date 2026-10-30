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
- One new compilation per ~10 songs, so a compilation is never thin.

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
python3 scripts/compile_album.py --name "รวมเพลงไทยเพื่อชีวิต" --max 60 --render
```

## Known gaps, stated plainly

- **19 of 20 songs are not generated yet.** Generation is window-gated; the
  batch is running and will fill in as windows open.
- **Karaoke subtitles are estimated**, not from real lyric timing. Flow Music
  does expose `lyrics_timing` on a clip; wiring it in would make the karaoke
  word-accurate. That is the next quality upgrade.

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
