# music938-1 — the plan to make AERIS Music a real channel

Owner: AR (full authority, K's standing delegation 2026-10-30). Budget: **0 baht,
forever** (K's Rule #1). Every tool below is free.

## The goal, in numbers

YouTube monetization needs **1,000 subscribers AND 4,000 qualified watch hours in
12 months** (or 1,000 subs and 10M Shorts views in 90 days). The channel today is
0 subs, 8 videos, 11m19s of catalogue, 442 lifetime views.

Watch hours are the binding constraint, not subscribers, and not song count.

## The arithmetic that decides the method

- One 3-minute song watched once = **0.05 h**. Songs alone would need ~80,000 views.
- One 60-minute compilation watched once = **1.0 h**. It would need ~4,000 views.
- Same songs. Same generation cost. **20x less audience for the same hours.**

So the release shape is not "20 songs". It is:

1. **20 songs**, each released twice — the song and the karaoke (one generation,
   two catalogue videos).
2. **Album compilations** — 60-minute runs of the songs acrossfaded, one upload,
   a full watch hour per view. This is the main lever.

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
- The first upload of the pack stays **private for K** to approve. `--public` is
  a deliberate opt-in, never a default.
- One new compilation per ~10 songs, so a compilation is never thin.

## Commands

```bash
# generate (window-aware; run it and leave it)
python3 scripts/build_songs.py --workers 2

# what would be released, and when
python3 scripts/release.py --plan --days 7

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
- **Song 01 is 2:59**, under the 3.5-minute floor. The Extend step did not
  rescue it. The floor is enforced on new takes; 01 predates it and should be
  regenerated when a window is open.
