# music938-1 — Thai karaoke song pack

Twenty Thai songs, each with lyrics, a **real sung vocal**, a karaoke mix, cover
art, and a 1920x1080 karaoke video with a word-synced highlight sweep.

The vocal comes from **Google Flow Music** (`flowmusic.app`), a free, login-only
web app. It is a real singing model, which is the whole point: see the note below
on why the first attempt at this pack was destroyed.

## Why the first attempt was destroyed (do not repeat it)

The first version synthesised the vocal with a **Piper Thai TTS voice pitch-shifted
onto a melody**. K ordered all 4.0 GB destroyed: *"งานเพลงแบบนี้คือล้มเหลวมากๆ"*.
That is not singing, and no amount of mixing fixes it.

**The rule this leaves behind:** a sung vocal cannot be produced by
post-processing a speaking voice. If the deliverable is a song and the only voice
available is TTS, say so before building anything — do not build twenty of them.
The free route to a real sung Thai vocal is Flow Music; the scripts here drive it.

## What is produced

Per song `<slug>`:

| Output | Path |
| --- | --- |
| Song (vocal + backing) | `library/songs/song-<slug>.mp3` |
| Karaoke mix (backing only) | `library/songs/karaoke-<slug>.mp3` |
| Cover art | `library/covers/cover-<slug>.jpg` |
| Karaoke video (1920x1080) | `library/karaoke/karaoke-<slug>.mp4` |
| Subtitles (estimated timing) | `work/<slug>/karaoke.ass` |
| Stem split of the master | `library/songs/stems-<slug>/*.m4a` |

## How a song is made

1. **Lyrics** live in `lyrics/*.txt`: a header block (`TITLE`, `SUBTITLE`, `KEY`,
   `MOOD`, `TEMPO`, `VOICE`) plus `[section]` markers and the sung lines.
2. **Generate** (`flow_song.py`) drives the signed-in Chromium on the cloud
   desktop: it fills the compose panel (sound description, lyrics, BPM, length),
   clicks Generate, then watches `POST /__api/clips` for the new clip to finish
   rendering and pulls its audio. A public GCS url is on the clip, so no download
   button is clicked.
3. **Length.** The create pass is clamped to **3:00** by the app (Lyria forces any
   longer request back to 180s), and length is baked into the lyrics as
   `[End - m:ss]`, not sent as a field. So a create is the seed and **Extend**
   (Remix -> Extend) carries a song into the 3.5-5 min brief. Extend is gated on
   the measured duration, so a long-enough take skips it.
4. **Karaoke** (`flow_song.py::_karaoke`). The preferred source is the model's own
   **4-stem split** (`GET /__api/stems/clip/<id>` -> vocals/drums/bass/other):
   drop the vocal stem and sum the rest for a clean instrumental. If stems are
   unavailable it falls back to a channel-subtraction center-cancel plus a
   low-passed mono restore.
5. **Video** (`make_karaoke.py`) burns ASS subtitles with one `\kf` sweep per
   word over the cover art, with a title card and a closing card.

## Usage

```bash
python3 scripts/build_songs.py           # all 20, resumable, backs off on 429
python3 scripts/build_songs.py --only 01,02
python3 scripts/flow_song.py 07-huachai-si-thao        # one song
python3 scripts/make_karaoke.py 07-huachai-si-thao --preview 30
python3 scripts/report.py                # what exists, and whether it meets the brief
python3 tests/run.py                     # fast offline checks
```

`build_songs.py` skips a song already on disk and re-runs it otherwise, so an
interrupted batch continues where it stopped.

## The rate limit is real and is not ours

Flow Music is a shared free service. `POST /__api/producer/tool-call` answers
`429 Too Many Requests` with no `Retry-After`, for **every** generation tool and
for a plain UI Generate. It is account-wide, not per-tool, and it is **not** a
credit problem: the account reads `free` tier with 6000 tokens / 500 credits
while every call 429s. It is intermittent — six songs rendered in a 26-minute
window on 2026-10-29 — so the batch walks the songs in order with a short backoff
ladder (240s..600s) and catches the next open window.

## Timing is estimated, and the code says so

The old version read a `timing.json` that the retired Piper builder wrote, where
every note was known. Flow Music does not return per-syllable timing by default
(`lyrics_timing` comes back `not_requested`), so `make_karaoke.py` estimates line
timing from the song length and each line's length and sweeps proportionally
inside a line. That is a lyric video with a karaoke sweep, not a note-accurate
one. If a clip ever carries `lyrics_timing.markers`, pass them with `--timing`
and the sweep uses the real times.

## Requirements

- `ffmpeg` (with `libass` for the `ass` filter) and `ffprobe`
- A signed-in Flow Music session on the cloud desktop
  (`.agents/skills/ax-cloud-desktop`), no credential is typed or stored
- Python: `playwright`, `numpy`, `pillow`, `pythainlp` (optional, for Thai word
  splitting in the sweep)
- Thai font `Noto Sans Thai` for the karaoke render

## Delivery

**Google Drive.** `scripts/gdrive-upload-browser.py` uploads through the
signed-in desktop browser (no API): `--folder "AX Content Lab/music938-1"
--glob 'music938-1/library/songs/*' --glob 'music938-1/library/karaoke/*'`. The
older `gdrive-upload.py` needs the Drive API enabled in the owning Cloud project,
which is an operator action.

## Dead scaffolding

`tts.py`, `make_song.py`, `music.py`, `audio.py`, `covers.py`, `build_all.py` and
`setup-env.sh` are the retired Piper synthesis pipeline. They are kept only as a
record of what was rejected; nothing in the Flow Music path calls them.

