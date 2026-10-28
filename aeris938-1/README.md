# aeris938-1 — Thai story content pipeline

Turns a Thai story script into a finished karaoke episode: narration, a
word-synced karaoke subtitle track, a per-story cover, an optional music bed, and
a rendered 1920x1080 MP4. Everything runs on the sandbox with no paid API.

## The one thing to understand first

The image and song generators (Gemini, Flow Music) are **login-only web apps**.
There is no free API for either. So this pipeline drives a **real headful
Chromium running on the sandbox**, which the operator signs into once through a
browser link. The agent then drives that already-authenticated session.

Nothing here asks for, stores or transmits a password. The operator types it
into their own browser; the session cookies stay in
`/workspace/ax-tools/aeris938-state/chrome-profile`. That path is deliberate: `$HOME`
is on the container overlay and is **discarded on a pod recycle**, so a profile kept
there loses the Google login every time. Only `/workspace` survives.

## Quick start

```bash
# 1. Start the cloud desktop (Xvfb + openbox + x11vnc + noVNC + Chromium)
aeris938-1/scripts/vnc-pass.sh 'choose-a-password'   # once
aeris938-1/scripts/desktop.sh up
aeris938-1/scripts/login-link.sh                     # prints the link

# 2. Sign in there (Gemini, Flow Music), then come back

# 3. Build an episode
python3 aeris938-1/scripts/make_story.py 01-hin-haeng-khwam-jam
```

Output lands in `aeris938-1/work/<story>/`. Assets land in `aeris938-1/library/`.

## Story format

`aeris938-1/stories/<name>.txt`:

```
# TITLE: หินแห่งความจำ
# SUBTITLE: เรื่องที่ 1 · นิทานไทย
# MOOD: calm thai folk, warm, slow, instrumental
# SCENE: หมู่บ้านไทยยามพระอาทิตย์ตก ริมแม่น้ำ

ในหมู่บ้านเล็กๆ ริมแม่น้ำ มีเด็กหญิงคนหนึ่งชื่อว่าแก้ว
ทุกเช้าเธอจะเดินไปที่วัด เพื่อนำข้าวให้พระ
```

`# KEY: value` lines are directives and are never spoken. Every other line is
narration. One clause per line, because the newline is what makes the voice
pause.

## Layout

| Path | Purpose |
| --- | --- |
| `scripts/desktop.sh` | Cloud desktop: Xvfb, openbox, x11vnc, noVNC, Chromium |
| `scripts/browser.py` | CDP plumbing shared by the generators |
| `scripts/thai_text.py` | Number spelling, spacing, the pause-preserving normaliser |
| `scripts/narration.py` | edge-tts synthesis + per-line timing |
| `scripts/karaoke.py` | Timing -> `\k`-timed ASS karaoke track |
| `scripts/covers.py` | Per-story cover art (needs PIL built with raqm) |
| `scripts/make_music.py` | Offline mood music bed, no account needed |
| `scripts/gemini_image.py` | Image generation through signed-in Gemini |
| `scripts/flow_music.py` | Song generation through signed-in Flow Music |
| `scripts/compose.py` | ffmpeg render, karaoke burn-in, loudness |
| `scripts/make_story.py` | The orchestrator |
| `scripts/library.py` | Asset manifests — the reason assets are reusable |
| `library/` | `img/`, `music/`, `covers/`, each with `manifest.json` |
| `work/<story>/` | Per-story intermediates and the finished clip |

## The library is the point

Every generated asset is recorded in a manifest keyed by a stable id, with its
size and SHA-256. A second run **reuses** what exists instead of regenerating it.
A lookup that misses returns `None`; it never guesses. Recording a missing or
zero-byte file is a hard error.

```bash
python3 -c "import sys;sys.path.insert(0,'aeris938-1/scripts');import library;print(library.summary())"
```

## Facts that cost time to learn

- **Thai digits must be spelled out.** edge-tts has no Thai number dictionary;
  `187` is read wrong or dropped. `thai_text.expand_numbers` handles เอ็ด / ยี่สิบ
  / ล้าน correctly.
- **Pauses come from newlines.** Collapsing newlines destroys the delivery.
- **Timing comes from boundary events, not a chars-per-second estimate.** The
  estimate was wrong by up to 2x.
- **Thai has no word spaces,** so karaoke segments come from `pythainlp`, and each
  line's duration is split across segments by character weight.
- **libass must burn the subtitles.** PIL alone needs raqm for correct Thai mark
  positioning; ffmpeg's `subtitles` filter gets it right and is what is used.
- **`loudnorm` must be two-pass with `linear=true`.** One pass missed the target
  by ~4 LU here (-21.1 vs -17.0).
- **`-vsync vfr` with `-r` is a hard error** on modern ffmpeg; use `-fps_mode cfr`.
- **ffmpeg input indices shift** when an optional input is omitted. They are
  counted explicitly, and a missing still falls back to a solid backdrop.
- **`flowmusic.app` is a third-party site, not Google.** The chain is
  `labs.google/fx/tools/music-fx` -> `flowmusic.google` (real Google, Google
  Trust Services cert) -> **`flowmusic.app`** (Cloudflare IP 104.26.x, Let's
  Encrypt cert). The app is a Next.js bundle that contacts no Google API — its
  only third-party requests are Google Fonts and GTM. It presents itself as
  "Google Flow Music" while not being served by Google, so it is treated as
  third-party: **the operator signs in there themselves and the agent never
  fills a credential in.** `flow_music.py` prints this warning every run.

## Music is generated automatically

`make_story.py` needs no manual music step. If `<story>-mood` is not already in
the library it reads the story's `# MOOD:` line, picks the closest preset and
synthesises a bed:

```
# MOOD: อบอุ่น สงบ เหมือนเล่านิทานให้ลูกฟัง   -> calm
# MOOD: sad warm thai folk, slow            -> sad
# MOOD: ลึกลับ ขลัง                          -> mystic
```

Presets: `calm`, `warm`, `sad`, `hopeful`, `mystic`, `epic`. An unrecognised
mood falls back to `calm` rather than failing. Override by generating a bed
yourself first:

```bash
python3 aeris938-1/scripts/make_music.py <story>-mood epic --duration 150
```

A **real track** beats the synthesised bed, and `make_story.py` prefers one. Generate
it in Flow Music, then register it under the mood key:

```bash
python3 -c "import sys;sys.path.insert(0,'aeris938-1/scripts');import library,pathlib;\
library.add('music','01-hin-haeng-khwam-jam-mood',pathlib.Path('<file>.mp3'),\
source='flowmusic-web',provider='www.flowmusic.app',mood='calm thai folk')"
```

`compose.py` loops a short track with `-stream_loop -1`, so a 3-minute song fills a
5-minute episode. `library.find('music', f'{name}-mood')` is the only lookup; a miss
falls back to the bed rather than failing.

The bed is still **not** generated unattended from the web, because `flowmusic.app` is
third-party (see below): the operator signs in and starts the song, the agent drives the
already-authenticated session and downloads the result.

## Tests

```bash
python3 -m pytest aeris938-1/tests/test_pipeline.py -q
```

44 tests. They call the real synthesiser and the real ffmpeg, because the
failures that matter here (silent audio, unshaped tone marks, a loudness target
missed by a decibel) are exactly the ones a mock would hide.
