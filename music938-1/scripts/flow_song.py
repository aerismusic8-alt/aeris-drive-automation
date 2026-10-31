#!/usr/bin/env python3
"""Generate one music938 song through Google Flow Music (the signed-in web app).

The first attempt at this pack synthesised the vocal with a Piper TTS voice
pitch-shifted onto a melody. K rejected it outright: that is not singing. Flow
Music is a real singing model and it is free with a Google account, so it is the
only source this pack may use.

Flow Music is login-only, so this drives the already-authenticated Chromium on
the cloud desktop. The operator signs in once through noVNC; nothing here types
or stores a credential.

A generated song is served from a public GCS bucket
(`producer-app-public/clips/<id>.m4a`), and the session's clip metadata (with
`audio_url` and the real duration) comes from `POST /__api/clips`. The driver
watches that endpoint, waits for the new clip to finish rendering, then pulls
the audio. No download button needs to be clicked.

    python3 scripts/flow_song.py 01-khon-di-thi-chak-pai
    python3 scripts/flow_song.py --list
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "aeris938-1" / "scripts"))

from playwright.sync_api import sync_playwright  # noqa: E402

import browser as B  # noqa: E402

SESSION_URL = "https://www.flowmusic.app/session?t=true"
OUT_DIR = ROOT / "library" / "songs"
COVER_DIR = ROOT / "library" / "covers"
LYRICS_DIR = ROOT / "lyrics"

# A full verse/chorus form with a real vocal settles near 3.5-4.5 min, inside
# the 3.5-5 min target.
STYLE = {
    "sad": "Thai luk-thung ballad, warm acoustic guitar, phin and khaen, slow "
           "sway, emotional lead vocal singing in Thai, gentle strings",
    "warm": "Thai folk-pop, acoustic guitar and khaen, mid-tempo, warm lead "
            "vocal singing in Thai",
    "hopeful": "Thai pop ballad, piano and strings, uplifting, clear lead vocal "
               "singing in Thai",
    "fun": "Thai mor-lam pop, upbeat, khaen and drums, cheerful lead vocal "
           "singing in Thai",
    # calm/epic/mystic are used by the pack, so they need their own sound. Without
    # an entry each fell back to "sad" and eight of the twenty songs would have
    # come out as the same ballad regardless of the mood in their header.
    "calm": "Thai acoustic folk, gentle fingerpicked guitar, soft khaen, "
            "slow and unhurried, tender lead vocal singing in Thai",
    "epic": "Thai cinematic pop, big drums and strings, soaring build, powerful "
            "lead vocal singing in Thai",
    "mystic": "Thai dream-pop, reverb-drenched guitar, sparse piano, atmospheric "
              "and nocturnal, airy lead vocal singing in Thai",
}


def parse_lyric(path: Path) -> dict:
    """Split a lyric file into its header block and the sectioned body."""
    meta, lines, in_body = {}, [], False
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if line.startswith("#"):
            m = re.match(r"#\s*([A-Z]+):\s*(.+)", line)
            if m:
                meta[m.group(1).lower()] = m.group(2).strip()
            continue
        if line.startswith("["):
            in_body = True
        if in_body:
            lines.append(line)
    body = "\n".join(lines).strip()
    # Flow Music reads [Verse] / [Chorus]; the files use lowercase tags.
    body = re.sub(r"\[(\w+)\]", lambda m: f"[{m.group(1).capitalize()}]", body)
    body = re.sub(r"\n{3,}", "\n\n", body)
    return {"meta": meta, "lyrics": body}


def style_for(meta: dict) -> str:
    mood = (meta.get("mood") or "").lower()
    base = STYLE.get(mood, STYLE["sad"])
    key = meta.get("key")
    return f"{base}. Key of {key}." if key else base


def _moods_in_use() -> set[str]:
    """Every MOOD value the lyric files declare."""
    moods = set()
    for f in sorted(LYRICS_DIR.glob("*.txt")):
        for line in f.read_text(encoding="utf-8").splitlines():
            m = re.match(r"#\s*MOOD\s*:\s*(\S+)", line)
            if m:
                moods.add(m.group(1).lower())
                break
    return moods


def _sung_line_count(path: Path) -> int:
    """Lines the model is asked to sing (no headers, no section tags)."""
    n = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if not s or s.startswith("#") or (s.startswith("[") and s.endswith("]")):
            continue
        n += 1
    return n


# The create pass is capped near 180s. A lyric of ~22 lines fills only part of
# that and leaves the take under the 3.5-minute floor even when Extend succeeds,
# so every song needs the full verse/chorus form the first song has.
MIN_SUNG_LINES = 30


def meta_bpm(meta: dict) -> str | None:
    tempo = (meta.get("tempo") or "").strip()
    return tempo if tempo.isdigit() else None


# Asked of the Lyria model. Every take recorded so far came back at 160-184s
# even with this set to "3:00", and the app folds the value into the lyrics as
# `[End - m:ss]`, so the Length field is a *seed* the model aims at rather than a
# hard cap. Ask for the floor outright and let Extend close the rest of the gap.
# Override with FLOW_CREATE_LENGTH to experiment without an edit.
CREATE_LENGTH = os.environ.get("FLOW_CREATE_LENGTH", "4:30")
# 3.5 min, the same floor report.py enforces, so a take that passes
# here cannot fail the brief later.
MIN_SECONDS = 210.0
# A create lands near 3:00 and one Extend adds a fixed step, so a take under the
# floor is extended until it clears the brief.
MAX_EXTENDS = 3
# An extend issued seconds after its own create lands in the same per-minute rate
# bucket and 429s. Resting first steps out of the bucket; measured 2026-10-31,
# the extend then returns `200` and a complete clip. Keep the rest.
EXTEND_REST_S = 150


def _open_compose(page):
    """The compose panel starts collapsed: its textareas have zero width until
    the panel is toggled open, so fill() would time out on a hidden element."""
    ta = page.locator('textarea[aria-label="Lyrics"]').first
    if ta.count() and ta.evaluate("e => e.getBoundingClientRect().width") == 0:
        btn = page.locator('button[aria-label="Toggle compose panel"]').first
        if btn.count():
            btn.click()
            page.wait_for_timeout(2500)


def _expand(page, section: str):
    """Lyrics and Sound start collapsed; their textareas exist but are hidden."""
    btn = page.locator(f'button[aria-label="Expand {section} section"]')
    if btn.count():
        btn.first.click()
        page.wait_for_timeout(400)


def _set_advanced(page, length: str, bpm: str | None):
    """Advanced mode exposes BPM and Length for the Lyria model.

    Length is mm:ss and is a *seed*, not a cap: the app clamps the create pass to
    3:00 and folds the value into the lyrics as `[End - m:ss]`. The 3.5-5 min
    brief is reached by Extend, not by asking for a longer create.
    The fields are addressed by their <label> sibling: the inputs share a
    placeholder ("Auto"), so index-based selectors hit the wrong one.
    """
    sw = page.locator('button[aria-label="Toggle advanced sound mode"]').first
    if sw.count() and sw.get_attribute("aria-checked") == "false":
        sw.click()
        page.wait_for_timeout(1500)

    def field(name: str):
        return page.locator(
            f"xpath=//label[normalize-space()='{name}']/following-sibling::input[1]")

    for name, val in (("BPM", bpm), ("Length", length)):
        if not val:
            continue
        el = field(name)
        if not el.count():
            raise RuntimeError(f"advanced {name} field not found")
        el.first.click()
        el.first.press("Control+a")
        el.first.press("Backspace")
        page.keyboard.insert_text(str(val))
        page.wait_for_timeout(500)


def _wait_composer(page, timeout=90_000):
    deadline = time.time() + timeout / 1000
    while time.time() < deadline:
        if page.locator('textarea[aria-label="Lyrics"]').count():
            return True
        # A fresh session opens on the producer chat; a login wall must be
        # reported rather than waited out.
        if "Free to start with a Google Account" in page.inner_text("body"):
            raise B.LoginRequired(B.login_instructions("Google Flow Music"))
        page.wait_for_timeout(1500)
    return False


def _attach_clips(page, clips: dict, flags: dict):
    def on_response(resp):
        if "/__api/clips" in resp.url:
            try:
                for cid, c in (resp.json().get("clips") or {}).items():
                    clips[cid] = c
            except Exception:
                pass
        elif "/__api/producer/tool-call" in resp.url and resp.status == 429:
            flags["rate_limited"] = True
    page.on("response", on_response)


def _sweep_tabs(ctx, keep: int = 2):
    """Close stale tabs left by a killed run. A dozen orphaned tabs makes the
    next run's CDP calls time out."""
    pages = list(ctx.pages)
    for pg in pages[:-keep] if len(pages) > keep else []:
        try:
            pg.close()
        except Exception:
            pass


def _wait_new_clip(page, clips, since: str, exclude: set, timeout: float,
                   kinds=("audio__create_song", "audio__extend_song"),
                   flags: dict | None = None):
    deadline = time.time() + timeout
    started = time.time()
    while time.time() < deadline:
        page.wait_for_timeout(5000)
        fresh = [c for c in clips.values()
                 if c.get("op_type") in kinds and c.get("audio_url")
                 and c.get("id") not in exclude
                 and c.get("created_at", "") >= since]
        if fresh:
            cand = max(fresh, key=lambda c: c.get("created_at", ""))
            if (cand.get("duration") or {}).get("status") == "completed":
                return cand
        # A 429 on the producer means the request was dropped. Bail out now
        # rather than sit out the full timeout: the batch runner backs off.
        if flags is not None and flags.get("rate_limited") and time.time() - started > 25:
            return None
    return None


def _download(page, clip, dest: Path):
    dest.write_bytes(page.request.get(clip["audio_url"]).body())


def _seconds(path: Path) -> float:
    return float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True).stdout.strip())


def _join(head: Path, tail: Path, dest: Path):
    """Append the extended segment to the base take.

    Extend sometimes returns only the new part, which is useless on its own.
    Re-encoding is required: both parts are AAC, and a stream copy of two AAC
    segments leaves the decoder with a corrupt first frame.
    """
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(head), "-i", str(tail),
         "-filter_complex", "[0:a][1:a]concat=n=2:v=0:a=1[out]",
         "-map", "[out]", "-c:a", "aac", "-b:a", "192k", str(dest)],
        check=True,
    )


def _cover(page, clip, dest: Path):
    """The model's own cover art, saved beside the audio.

    A song with no artwork gets a flat placeholder instead, so the pack always
    has one image per track.
    """
    url = clip.get("image_url")
    if url:
        try:
            dest.write_bytes(page.request.get(url).body())
            return True
        except Exception:
            pass
    return False


def _save_clip_meta(clip: dict, dest: Path) -> None:
    """Persist the master clip's own lyrics and timing next to the audio.

    The clip carries the lyrics the model actually sang plus a `lyrics_timing`
    field. Timing is `not_requested` until a producer call fills it, and that
    call is throttled, so it is saved as-is: when a later run requests it, the
    karaoke can become word-accurate without regenerating the song. The sung
    text is worth keeping regardless, since it is what the vocal really says.
    """
    keep = {k: clip.get(k) for k in
            ("id", "title", "duration", "op_type", "created_at",
             "lyrics", "lyrics_timing", "has_vocals")}
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(keep, ensure_ascii=False, indent=1), encoding="utf-8")


def _stems(page, clip_id: str, dest: Path) -> dict | None:
    """Fetch the model's own 4-stem split for a clip.

    `GET /__api/stems/clip/<id>` returns vocals/drums/bass/other as base64 M4A.
    It is a plain read (no producer tool-call), so it is not subject to the
    generation throttle, and it gives a true instrumental: the vocal stem is
    simply left out rather than guessed at with a center-cancel.

    The endpoint needs the app's Supabase bearer token, which a bare `fetch`
    from the page does not carry, so the token is captured off a real app
    request first.
    """
    tok: dict = {}
    page.on("request", lambda r: tok.setdefault("v", r.headers["authorization"])
            if "/__api/" in r.url and "authorization" in r.headers else None)
    try:
        page.goto(SESSION_URL, wait_until="domcontentloaded", timeout=60_000)
        for _ in range(30):
            if "v" in tok:
                break
            page.wait_for_timeout(1000)
    except Exception:
        pass
    if "v" not in tok:
        return None
    try:
        d = page.evaluate(
            """async ([id, t]) => {
                 const r = await fetch('/__api/stems/clip/' + id,
                                       {headers: {'Authorization': t}});
                 if (!r.ok) return null;
                 return await r.json();
               }""", [clip_id, tok["v"]])
    except Exception:
        return None
    stems = (d or {}).get("stems") or {}
    if not stems:
        return None
    dest.mkdir(parents=True, exist_ok=True)
    out = {}
    for name, b64 in stems.items():
        p = dest / f"{name}.m4a"
        p.write_bytes(base64.b64decode(b64))
        out[name] = p
    return out


def _karaoke(src: Path, dest: Path, stems: dict | None = None):
    """Make the karaoke mix.

    Preferred path: the model's own stems. Dropping the `vocals` stem and
    summing drums+bass+other is a clean instrumental with no vocal bleed.
    Fallback (no stems available): a channel-subtraction center-cancel. A
    centered lead vocal cancels and the sides survive, but the centered bass
    and kick go with it, so a low-passed mono sum is mixed back in. The result
    is normalised to a karaoke level either way.
    """
    if stems and {"drums", "bass", "other"} <= stems.keys():
        ins = [str(stems[k]) for k in ("drums", "bass", "other")]
        graph = "".join(f"[{i}:a]" for i in range(len(ins)))
        graph += (f"amix=inputs={len(ins)}:normalize=0,"
                  "loudnorm=I=-16:TP=-1.5:LRA=11[out]")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error",
             *[a for p in ins for a in ("-i", p)],
             "-filter_complex", graph, "-map", "[out]",
             "-codec:a", "libmp3lame", "-qscale:a", "2", str(dest)],
            check=True,
        )
        return

    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src),
         "-filter_complex",
         "[0:a]pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0[cc];"
         "[0:a]lowpass=f=160,pan=mono|c0=0.5*c0+0.5*c1,volume=1.4[bass];"
         "[cc][bass]amix=inputs=2:weights=1 1:normalize=0,"
         "loudnorm=I=-16:TP=-1.5:LRA=11[out]",
         "-map", "[out]", "-codec:a", "libmp3lame", "-qscale:a", "2", str(dest)],
        check=True,
    )


def _open_extend(page):
    """Open Remix -> Extend and return True when the panel is up.

    The panel is flaky: the Remix menu can open before Extend is mounted, so
    this retries the whole open sequence. Success is the panel's own
    "Extend <from>-<to>" label, not a text field: the length is a drag range,
    so there is nothing to type.
    """
    for _ in range(3):
        btn = page.locator('button[aria-label="Remix"]').first
        btn.wait_for(state="visible", timeout=30_000)
        btn.click(timeout=15_000)
        page.wait_for_timeout(3500)
        page.evaluate("""() => {
          const els=[...document.querySelectorAll('button,div,span,a,li')]
            .filter(e=>(e.innerText||'').trim()==='Extend');
          if (els.length) els[els.length-1].click();
        }""")
        page.wait_for_timeout(4500)
        if page.locator('textarea[aria-label="Instruction"]').count():
            return True
    return False


def _extend(page, clip_id: str, clips: dict, since: str, exclude: set,
            timeout: float = 420.0, flags: dict | None = None):
    """Open Remix -> Extend and render the song out longer.

    This is the step that reaches the 3.5-5 min brief: the create pass is clamped
    to 3:00, so a seed take is always short. The panel extends by a default step;
    the instruction is what keeps the singer and key the same.
    """
    page.goto(f"https://www.flowmusic.app/song/{clip_id}",
              wait_until="networkidle", timeout=60_000)
    page.wait_for_timeout(5000)

    if not _open_extend(page):
        raise RuntimeError("extend panel did not open")

    instr = page.locator('textarea[aria-label="Instruction"]').first
    instr.click()
    page.keyboard.insert_text(
        "Continue with a final chorus and a gentle outro, same singer and same key")
    page.wait_for_timeout(500)

    page.evaluate("""() => {
      const bs=[...document.querySelectorAll('button,div,a')]
        .filter(e=>(e.innerText||'').trim()==='Generate');
      if (bs.length) bs[bs.length-1].click();
    }""")
    # An extend comes back as an `audio__render_edit` clip, not
    # `audio__extend_song`: Flow re-renders the whole take with the appended
    # section. Waiting only for `audio__extend_song` therefore never saw it, so
    # every extend looked like a failure (the old "16 creates, 0 extends" note)
    # while the clip was in fact produced, complete, and over the floor.
    return _wait_new_clip(page, clips, since, exclude, timeout,
                          kinds=("audio__extend_song", "audio__render_edit"),
                          flags=flags)


def generate(slug: str, *, timeout: float = 480.0, force: bool = False,
             keep_tabs: bool = False) -> dict:
    lyric_path = LYRICS_DIR / f"{slug}.txt"
    if not lyric_path.exists():
        raise SystemExit(f"no lyric file: {lyric_path}")
    out = OUT_DIR / f"song-{slug}.mp3"
    kar = OUT_DIR / f"karaoke-{slug}.mp3"
    if out.exists() and kar.exists() and not force:
        # Existence is not enough: a take from before the floor was enforced can
        # be under 3.5 min and still sit on disk. Rebuild those.
        if _seconds(out) >= MIN_SECONDS:
            return {"status": "EXISTS", "file": str(out), "karaoke": str(kar)}
        print(f"[warn] {slug}: existing take is {_seconds(out):.1f}s, rebuilding",
              file=sys.stderr)

    song = parse_lyric(lyric_path)
    if len(song["lyrics"]) > 3000:
        raise SystemExit(f"{slug}: lyrics {len(song['lyrics'])} chars > 3000 limit")

    clips: dict = {}
    flags: dict = {}
    before = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    COVER_DIR.mkdir(parents=True, exist_ok=True)
    raw = OUT_DIR / f"song-{slug}.m4a"

    with sync_playwright() as p:
        br, ctx = B.connect(p)
        if not keep_tabs:
            # Only safe when this is the sole worker: sweeping would close a
            # sibling worker's tab mid-generation.
            _sweep_tabs(ctx)
        page = ctx.new_page()
        try:
            _attach_clips(page, clips, flags)

            page.goto(SESSION_URL, wait_until="domcontentloaded", timeout=60_000)
            page.wait_for_timeout(4000)
            if not _wait_composer(page):
                raise B.LoginRequired(B.login_instructions("Google Flow Music"))

            # Instrumental must be off: this pack needs a sung vocal.
            sw = page.locator('button[aria-label="Toggle instrumental mode"]').first
            if sw.count() and sw.get_attribute("aria-checked") == "true":
                sw.click()
                page.wait_for_timeout(500)

            _open_compose(page)
            _expand(page, "Lyrics")
            _expand(page, "Sound")
            page.fill('textarea[aria-label="Sound description"]', style_for(song["meta"]))
            page.fill('textarea[aria-label="Lyrics"]', song["lyrics"])
            _set_advanced(page, length=CREATE_LENGTH, bpm=meta_bpm(song["meta"]))
            page.wait_for_timeout(800)

            page.get_by_role("button", name="Generate", exact=True).click()
            base = _wait_new_clip(page, clips, before, exclude=set(), timeout=timeout,
                                  flags=flags)
            if not base:
                page.screenshot(path=str(ROOT / "work" / f"fail-{slug}.png"))
                if flags.get("rate_limited"):
                    raise B.RateLimited(slug)
                raise TimeoutError(f"{slug}: no completed create clip in {timeout:.0f}s")
            _download(page, base, raw)
            _cover(page, base, COVER_DIR / f"cover-{slug}.jpg")

            # Create is clamped near 3:00 and one Extend adds a fixed ~60s step,
            # so a single extend lands under the floor. Extend again, each time
            # on the newest clip, until the running take clears the brief.
            source = raw
            current = _seconds(raw)
            junk = []
            master = base
            extended = False
            for attempt in range(MAX_EXTENDS):
                if current >= MIN_SECONDS:
                    break
                if attempt == 0:
                    # Step out of the create's own rate bucket before asking for
                    # an extend; see EXTEND_REST_S.
                    print(f"[info] {slug}: resting {EXTEND_REST_S}s before extend",
                          file=sys.stderr)
                    time.sleep(EXTEND_REST_S)
                since2 = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                flags["rate_limited"] = False
                try:
                    ext = _extend(page, master["id"], clips, since2,
                                  {master["id"]}, flags=flags)
                except Exception as exc:  # the panel is flaky; keep what we have
                    print(f"[warn] {slug}: extend {attempt + 1} failed: {exc}",
                          file=sys.stderr)
                    ext = None
                if not ext:
                    if flags.get("rate_limited"):
                        raise B.RateLimited(slug)
                    page.screenshot(path=str(ROOT / "work" / f"extfail-{slug}.png"))
                    break
                part = raw.with_name(f"{slug}-ext{attempt + 1}.m4a")
                _download(page, ext, part)
                _cover(page, ext, COVER_DIR / f"cover-{slug}.jpg")
                junk.append(part)
                pd = _seconds(part)
                if pd > current + 5:
                    # A full re-render, already longer: use it whole.
                    source, current = part, pd
                else:
                    # Only the appended tail came back: splice it on.
                    merged = part.with_name(part.stem + "-merged.m4a")
                    _join(source, part, merged)
                    junk.append(merged)
                    source, current = merged, _seconds(merged)
                master = ext
                extended = True
        finally:
            # A failed run must not leave its tab behind: a dozen orphaned tabs
            # makes the next run's CDP calls time out.
            page.close()

    if not raw.exists() or raw.stat().st_size == 0:
        raise RuntimeError(f"{slug}: empty download")

    # `source` is already the longest form the extends produced (a re-render or a
    # spliced tail), built inside the loop above.
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(source),
         "-codec:a", "libmp3lame", "-qscale:a", "2", str(out)],
        check=True,
    )
    for part in junk:
        part.unlink(missing_ok=True)
    raw.unlink(missing_ok=True)

    # A take below the floor is not a song for this pack. Writing it would make
    # the batch skip the slug forever (it resumes on "song-*.mp3 exists"), so a
    # short take is discarded and reported as retryable instead.
    dur = _seconds(out)
    if dur < MIN_SECONDS:
        out.unlink(missing_ok=True)
        if flags.get("rate_limited"):
            raise B.RateLimited(slug)
        raise B.TooShort(slug, dur)

    # The clip id that ends up being the master is the one to split. This is a
    # plain read, so a throttle on generation does not affect it.
    master_id = master["id"]
    _save_clip_meta(master, OUT_DIR / f"clipmeta-{slug}.json")
    stem_dir = OUT_DIR / f"stems-{slug}"
    with sync_playwright() as p2:
        br2, ctx2 = B.connect(p2)
        pg2 = ctx2.new_page()
        try:
            stems = _stems(pg2, master_id, stem_dir)
        finally:
            pg2.close()
    _karaoke(out, kar, stems=stems)
    return {"status": "CREATED", "file": str(out), "karaoke": str(kar),
            "seconds": round(dur, 1), "bytes": out.stat().st_size,
            "clip_id": base["id"], "extended": extended}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--keep-tabs", action="store_true",
                    help="do not sweep other tabs; set when workers run in parallel")
    ap.add_argument("--check", action="store_true",
                    help="verify every lyric MOOD has a style, then exit")
    args = ap.parse_args()
    if args.check:
        used = _moods_in_use()
        missing = {m for m in used if m not in STYLE}
        for mood in sorted(used):
            mark = "ok " if mood in STYLE else "MISSING"
            print(f"  {mark:8} {mood}")
        if missing:
            print(f"\n{len(missing)} mood(s) would fall back to 'sad': "
                  f"{', '.join(sorted(missing))}", file=sys.stderr)
            return 1
        print(f"\nall {len(used)} moods have their own style")

        short = []
        for f in sorted(LYRICS_DIR.glob("*.txt")):
            n = _sung_line_count(f)
            if n < MIN_SUNG_LINES:
                short.append((f.stem, n))
        if short:
            print(f"\n{len(short)} lyric(s) are too short to fill the brief "
                  f"(need {MIN_SUNG_LINES}+ sung lines):", file=sys.stderr)
            for slug, n in short:
                print(f"  {n:3} lines  {slug}", file=sys.stderr)
            return 1
        print(f"all lyrics have {MIN_SUNG_LINES}+ sung lines")
        return 0
    if args.list:
        for f in sorted(LYRICS_DIR.glob("*.txt")):
            print(f.stem)
        return 0
    if not args.slug:
        ap.error("need a slug (or --list)")
    try:
        r = generate(args.slug, force=args.force, keep_tabs=args.keep_tabs)
    except B.LoginRequired as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except B.RateLimited:
        print(json.dumps({"status": "RATE_LIMITED", "slug": args.slug}))
        return 4
    except B.TooShort as exc:
        print(json.dumps({"status": "TOO_SHORT", "slug": args.slug,
                          "seconds": round(exc.seconds, 1)}))
        return 5
    print(json.dumps(r, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
