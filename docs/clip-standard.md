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
| `vertical` | 1080×1920 | 30 | short, MV, affiliate, surreal, concert, moods | not frozen |
| `film` | 1920×1080 | 30 | film / long-form landscape | (cuts by design — no style rule) |
| `horizontal` | 1920×1080 | 25 | karaoke, compilation | (a lyric sheet is nearly still) |
| `motion` | 832×480 | 16 | internal motion asset | silent allowed |

A profile may **tighten** any floor value and add style rules. A style rule is
applied only where the format calls for it — that is the point of splitting the
floor from the style:

- **No hard cut** belongs to trivia. A public-domain film cuts between shots by
  design (measured max frame-delta ~90); holding it to the trivia rule would be a
  false failure.
- **Not frozen** belongs to trivia and the vertical lanes. A karaoke lyric sheet
  is meant to be almost still (measured 0.0).
- **Caption present** is checked on trivia (white Thai on footage) and is not
  reliable on karaoke (white lyric on video — the heuristic cannot see it).

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
