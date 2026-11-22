# The channel clip standard — every format, one floor

K (2026-11-17): the trivia clip he supplied is **only a sample** of the quality he
wants — "อันนี้เป็นแค่มาตรฐานเริ่มต้น ... **ห้ามมาตรฐานต่ำกว่านี้เด็ดขาดในช่องของเรา**".
The goal is a standard for **all** our work, not one lane. This document is that
standard; `ops/clip_standard.py` is its enforceable form.

> A rule in a document drifts. A rule measured on every clip does not. Nothing
> below this floor may ship on any channel — the upload path measures it.

Everything is free (Rule #1): ffprobe + ffmpeg only. No key, no account.

## 1. The universal floor (every format)

| Property | Floor |
| --- | --- |
| Video codec | h264 |
| Pixel format | yuv420p (or yuvj420p) |
| Audio codec | aac, 48 kHz, stereo |
| Loudness | −16.0 .. −12.0 LUFS (target −14) |
| True peak | ≤ −1.0 dBTP — no clipping |
| Length | ≥ 1 s |

The loudness band is the streaming-master norm (YouTube normalises playback to
about −14 LUFS). The true-peak ceiling is what stops the distortion that makes a
phone speaker buzz. A clip outside the band is not "loud", it is unmastered.

## 2. One profile per format we actually render

Measured from the live library on 2026-11-17:

| Profile | Shape | fps | Lanes | Extra rules |
| --- | --- | --- | --- | --- |
| `trivia` | 1280×720 | 24 | เกร็ดความรู้ | not frozen, no hard cut, caption |
| `bank` | 720×1280 | 30 | the clip lane (`library/bank/`, the warehouse) | not frozen, no bars |
| `short` | 1080×1920 | 30 | short (hook lane, `library/shorts/`) | not frozen, caption, no bars |
| `vertical` | 1080×1920 | 30 | MV, affiliate, surreal, concert, moods | not frozen, no bars |
| `film` | 1920×1080 | 30 | film / long-form landscape | (cuts by design — no style rule) |
| `horizontal` | 1920×1080 | 25 | karaoke, compilation | (a lyric sheet is nearly still) |
| `motion` | 832×480 | 16 | internal motion asset | silent allowed |

### Why the clip lane renders 720p, not 1080p

K (2026-11-20): "คุณภาพวีดีโอใช้ภาพ 4k outputงาน720p" — 4K sources, 720p output.

The number is not a concession, it is what the source can support. Measured over
the committed photo bank (6,876 rows, 2026-11-20):

| Render | 9:16 crop needs | Rows that clear it without upscaling |
| --- | --- | --- |
| 1080×1920 | 1080 px | 1,704 / 6,876 = **24%** |
| 720×1280 | 720 px | 5,579 / 6,876 = **81%** |

A 1080 render therefore upscales three frames in four, and an upscale is exactly
the softness and grain the reviews named. Rendering 720 downsamples instead: the
frame stays crisp and the file is a quarter of the size. `bank` is a separate
profile so this does **not** lower the floor on `short` or `vertical`, which are
still held to 1080×1920.

Two rules apply to every profile with audio, because the loudness band cannot
see either defect:

- **No dead silence** — the longest gap must be ≤ 3 s (`silencedetect` at −45 dB).
  Integrated LUFS and true peak both stay in band across a dead stretch, so a
  broken render passed the audio floor before this rule existed.
- **Constant frame rate** — `avg_frame_rate` must agree with `r_frame_rate` within
  2%. A concat of a 30 fps and a 24 fps render reads 33.75 against a real 30
  (12.5% drift) while its nominal rate still looks legal.

A profile may **tighten** any floor value and add style rules. A style rule is
applied only where the format calls for it — that is the point of splitting the
floor from the style:

- **No hard cut** belongs to trivia. A public-domain film cuts between shots by
  design (measured max frame-delta ~90); holding it to the trivia rule would be a
  false failure.
- **Not frozen** belongs to trivia and the vertical lanes. A karaoke lyric sheet
  is meant to be almost still (measured 0.0).

  Read it as "the picture moves at all", not as "the camera moved enough". The
  number is the mean frame-to-frame difference, so it tracks *texture* as much as
  movement: a smooth synthetic still panning 52 px over 2.4 s scored 0.066 while
  a detailed photograph panning scored 8.7 (measured 2026-11-22, both from the
  clip lane). A near-zero median on a stills clip is not proof of a frozen
  picture — measure the displacement before deleting the render, and judge the
  material by where it came from (a 1024 px still upscaled to 720×1280 is soft
  even while it pans).
- **Caption present** is checked on trivia (white Thai on footage) and on the
  `short` lane, which is watched muted so text is mandatory. It is **not** checked
  on `vertical`: an MV shows artwork, not subtitles, and holding it to a text
  floor blocked a finished video (2026-11-19). It is also not reliable on karaoke
  (white lyric on video — the heuristic cannot see it).
- **No black bars** applies to every 9:16 profile: wasted screen is a defect
  whatever the lane. Only *edge-anchored* bands count, so a dark scene is not
  mistaken for a letterbox.

`short` and `vertical` share 1080×1920/30, so shape cannot tell them apart. The
lane is read from the path first (`LANE_PROFILE`), and `SHAPE_DEFAULT` maps an
unnamed 1080×1920 clip to the permissive `vertical` profile.

## 3. How it is enforced

| Where | What happens |
| --- | --- |
| `ops/trivia_reel.py` | runs the gate after every render; a fail **deletes the MP4 and exits non-zero** |
| `ops/yt_publish.py` | the one YouTube upload chokepoint for all 4 channels — measures every clip and **blocks** a below-floor one |
| `ops/fb_graph.py` / `ops/tiktok_api.py` | the Facebook / TikTok API posters call `assert_ok` before any network call |
| `music938-1/scripts/crosspost.py` | the browser composers `post_tiktok` / `post_facebook` call `assert_ok` first |
| `music938-1/tests/run.py` | `test_clip_standard_is_a_floor` pins the floor (may only be raised), builds deliberately bad clips to prove the gate rejects them, and asserts every upload path is gated before the insert |

The rule is **every channel, every route**. A below-floor clip has no path to a
channel: there is **no override**. Fix the clip (or re-master the song) and retry.

## 4. The defect this found, and the fix

The gate's first run over the real library found that **24 of 28 song masters sat
above 0 dBTP** (up to +1.6) and ranged −11.9 to −24.0 LUFS. The lanes mux those
masters raw, so every Short, MV, film and karaoke inherited the clipping.

- It is **not** a bug in `make_song.py`: its two-pass loudnorm reproduces
  −14.1 LUFS / −13.1 dBTP correctly, and MP3 encoding adds no overshoot. The
  masters are stale artifacts from before that path.
- The fix is `ops/remaster_songs.py` (free, ffmpeg only): it brings each master
  into the band and is idempotent, so it only touches a master that is out of it.

```
python3 ops/remaster_songs.py --dry-run     # report
python3 ops/remaster_songs.py               # fix every out-of-band master
```

The masters are gitignored and pulled from the `media-938` release, so a fix is
only durable once the release assets are refreshed (`scripts/publish_media.py`).

## 5. Normalise at the mux, not the master

The floor is measured on the **clip**, so the clip's own mux is where the audio
must be normalised. The masters were already in band, yet every lane below failed
the gate on loudness or true peak — because the render scripts wrote the song's
raw samples into the container.

- Each lane's mux filter (`make_short`, `make_karaoke`, `make_music_video`,
  `make_film_video`) carries `loudnorm=I=-14:TP=-2.0:LRA=11`, then
  `alimiter=limit=0.7:level=0`, then `-ar 48000`.
- **`alimiter` must be `level=0`.** The default `level` auto-normalises after
  limiting and *raised* a true peak of −0.3 dBTP to +0.7 — the limiter made
  clipping worse. With `level=0` the ceiling holds (measured −2.6 dBTP).
- **One-pass `loudnorm` is approximate on true peak.** `TP=-2.0` alone left the
  output at −0.3 dBTP on a dense master; the limiter is what makes the ceiling
  real. Test on the *loudest* master, not a quiet one.
- **`-ar 48000` is mandatory.** `loudnorm` upsamples to 192 kHz internally, so
  the aac encoder picks 96 kHz unless the rate is pinned — the gate wants 48 kHz.

The lane is the last place the audio can be fixed before the container is sealed;
a fix in the master never reaches a clip the lane already wrote.

## 6. Changing the standard

Raising a threshold is welcome and encouraged. Lowering one is exactly what K
forbade. If a rule turns out to be a false positive on a real, correct clip, fix
the *rule* (as the karaoke text rule was removed) — never lower the floor to make
a bad clip pass.
