# เกร็ดความรู้ clip — the production standard

This is the standard for the "เกร็ดความรู้รอบตัวและวิทยาศาสตร์" (everyday-science
trivia) clips. K supplied a reference clip on 2026-11-17 and asked for that
quality first, then to make it the standard. The numbers below are **measured**
from that reference, not chosen by taste, and `music938-1/tests/run.py::
test_trivia_reel` pins them so a change that drifts fails the suite.

Everything is free (Rule #1): edge-tts voice, licence-checked Wikimedia Commons
footage, ffmpeg. No key, no account, no login.

## The measured spec (1280×720, 4.03 s reference)

| Property | Reference | Our standard |
| --- | --- | --- |
| Container | MP4, h264 High L3.1, yuv420p | same |
| Size / rate | 1280×720, 24 fps | same |
| Video bitrate | ~2.29 Mbps | ≤2.3 Mbps (`-maxrate`) |
| Audio | AAC-LC 48 kHz stereo 129 kbps | same |
| Loudness | −14.9 LUFS, −2.6 dBTP | −15.0 LUFS, −2.5 dBTP |
| Background | real moving footage, no cuts, no zoom | real Commons footage + 0.5 s crossfade |
| Text | white Thai, ~3 px dark outline, no shadow | same |
| Text size | line height 73 px → font ~72 px | 72 px |
| Text position | left margin 134 px (10.5 %), block centre 48 % | same |

## Why each factor matters, in order

1. **A real moving picture.** The reference is drifting clouds, not a photo.
   A static still with a slow zoom reads as a slideshow and is the single
   biggest gap between "AI channel" and "made". `ops/footage_rail.py` searches
   Wikimedia Commons (~76k CC0/PD/CC BY videos) with no key.
2. **Loudness-normalised speech.** Raw edge-tts lands near −22 LUFS and varies
   clip to clip. `loudnorm` to −15 LUFS makes it sound like a finished edit and
   keeps a playlist level.
3. **Clean, large, left-anchored text** with a thin outline. No lower-third bar,
   no logo on the body cards — the reference carries neither.
4. **No hard cuts.** Consecutive backgrounds crossfade so the eye never sees a
   seam; the reference has zero cuts in its 4 s.

## The steps (what to run)

```bash
# 1. Write the script: a plain .md, one card per blank-line-separated block.
#    # TITLE: ...   and   # THEME: sky|water|space|plants|earth|body|weather|light
#    (see scripts_trivia/sky-blue.md)

# 2. Dry-run: check card count and estimated narration length.
python3 ops/trivia_reel.py --plan --script scripts_trivia/sky-blue.md

# 3. Render. Free footage is fetched first; stills are the fallback.
python3 ops/trivia_reel.py --script scripts_trivia/sky-blue.md --out /tmp/trivia
#    --stills-only   to force the stills path
#    --card-secs N   to change how many seconds of picture per card

# 4. Verify (never trust the render; read the numbers):
ffprobe -v error -show_entries stream=width,height,r_frame_rate,bit_rate \
        -of default=noprint_wrappers=1 /tmp/trivia/sky-blue.mp4
ffmpeg -hide_banner -i /tmp/trivia/sky-blue.mp4 \
       -af loudnorm=print_format=summary -f null -      # expect ~ -15 LUFS
```

## Pacing

Thai narration runs ~13.6 characters/second (male voice, rate −8 %). A 20–30 s
clip is 3–5 cards of 40–90 characters each. One card = one idea; the first card
is the question, the rest answer it.

## What the clip must NOT carry

- No paid stock, no key, no login (Rule #1).
- No logo/watermark on the body cards; the reference has none. The brand and the
  AI note live in the title and the description.
- No hard cut between pictures.

## Publishing (once the standard clip is approved)

The closing card carries `branding.FOLLOW_ASK` + `FOLLOW_PROMISE` ("กดติดตาม NEO
VINCI" / "เพลงใหม่ทุกวัน"), which is K's rule that every clip ends with the ask.
The description carries `branding.DESCRIPTION`, `branding.HASHTAGS`, the
`branding.LABEL` AI line, and `footage_rail.credits_block` for any CC BY/BY-SA
footage used. Upload is blocked on the YouTube Data API quota (403 quotaExceeded
across all four channels on 2026-11-17); it resumes when the daily quota resets.
