# เกร็ดความรู้ clip — the production standard

This is the standard for the "เกร็ดความรู้รอบตัวและวิทยาศาสตร์" (everyday-science
trivia) clips. K supplied a reference clip on 2026-11-17 and asked for that
quality first, then to make it the standard.

> **The standard is a floor, not a target.** K (2026-11-17): "อันนี้เป็นแค่
> มาตรฐานเริ่มต้น ... **ห้ามมาตรฐานต่ำกว่านี้เด็ดขาดในช่องของเรา**" — nothing below
> this may ship. The floor is enforced by `ops/clip_standard.py`, which measures a
> finished clip and rejects it; `ops/trivia_reel.py` runs that gate at the end of
> every render and **deletes the file and raises** if it fails. Raising a number is
> welcome; lowering one is the thing K forbade.

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

## The floor, enforced (`ops/clip_standard.py`)

A doc drifts, so the floor is machine-checked. `check(clip)` measures a finished
file and returns one row per rule; `assert_ok(clip)` raises on any fail.

```bash
python3 ops/clip_standard.py /tmp/trivia/sky-blue.mp4        # human table
python3 ops/clip_standard.py /tmp/trivia/sky-blue.mp4 --json # machine
```

| Rule | Floor | Why |
| --- | --- | --- |
| landscape | exactly 1280×720 | the format |
| frame rate | 24/25/30 fps | a real frame rate |
| video codec | h264 | widely playable |
| audio | aac, 48000 Hz, 2 ch | the reference |
| long enough | ≥ 3 s | not a flash |
| loudness | −16.5 … −13.5 LUFS | raw TTS is ~−22 |
| true peak | ≤ −1.0 dBTP | no clipping |
| no hard cut | consecutive-frame Δ ≤ 20 | a cut measures ~94 |
| not frozen | median Δ ≥ 0.15 | a still frame is 0.0 |
| caption present | ≥ 120 text px | white Thai + thin dark outline |

`ops/trivia_reel.py` runs this gate at the end of every render: on a fail it
**deletes the MP4 and exits non-zero**, so a below-floor clip can never leave the
machine as a finished artifact. `test_clip_standard_is_a_floor` pins the
thresholds and proves the gate rejects a bad clip.

## What the clip must NOT carry

- No paid stock, no key, no login (Rule #1).
- No logo/watermark on the body cards; the reference has none. The brand and the
  AI note live in the title and the description.
- No hard cut between pictures.

## Publishing (the clip is approved and reaches the channel)

The closing card carries `branding.FOLLOW_ASK` + `FOLLOW_PROMISE` ("กดติดตาม NEO
VINCI" / "เพลงใหม่ทุกวัน"), which is K's rule that every clip ends with the ask.
The description carries `branding.LABEL` AI line, the `monetize.cta` subscribe
ask, the socials footer, the footage credits and the trivia hashtags.

`ops/trivia_publish.py` is the half that turns a finished clip into a channel
upload — render, title, description, thumbnail, ledger:

```bash
python3 ops/trivia_publish.py --script scripts_trivia/sky-blue.md --dry-run
python3 ops/trivia_publish.py --next --now       # the next unposted fact
```

- The title leads with the **question** (the query a viewer types) and appends
  the series + `#เกร็ดความรู้`, so search can find it on a zero-subscriber channel.
- The thumbnail is a mid-clip frame (60 % of the runtime, a settled card) held to
  `ops/thumb_standard.py`, the same floor every channel thumb meets.
- The upload goes through `ops/yt_publish.py`, the one chokepoint, so both the
  clip floor and the thumbnail floor are enforced before any network call.
- `music938-1/work/trivia-state.json` records every posted fact, so a re-run or a
  retry never double-posts one.

`.github/workflows/ax-music-trivia.yml` runs `--next --now` once a day. YouTube's
per-channel daily new-video cap returns `uploadLimitExceeded` when the channel has
already taken its quota of new videos that day; that is a normal, non-fatal
outcome — the ledger records only successes, so the same fact lands on the next
tick.

`ops/trivia_reel.py` also enforces the clip floor at the end of every render: on
a fail it **deletes the MP4 and exits non-zero**, so a below-floor clip can never
leave the machine as a finished artifact.

