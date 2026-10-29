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


def meta_bpm(meta: dict) -> str | None:
    tempo = (meta.get("tempo") or "").strip()
    return tempo if tempo.isdigit() else None


# Asked of the Lyria model. The create pass is clamped to 3:00 (the app forces
# any longer request back to 180s), so this is the seed length and Extend is what
# carries a song into the 3.5-5 min brief.
CREATE_LENGTH = "3:00"
MIN_SECONDS = 205.0


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

    Length is mm:ss. Without it the model picked its own length (~3:00), under
    the 3.5 min floor; setting it is what puts a song in the 3.5-5 min range.
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

    A single create pass honours Length up to 5:00, so this is only a fallback
    for a take the model returned short. The panel extends by a default step;
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
    return _wait_new_clip(page, clips, since, exclude, timeout, flags=flags)


def generate(slug: str, *, timeout: float = 480.0, force: bool = False) -> dict:
    lyric_path = LYRICS_DIR / f"{slug}.txt"
    if not lyric_path.exists():
        raise SystemExit(f"no lyric file: {lyric_path}")
    out = OUT_DIR / f"song-{slug}.mp3"
    kar = OUT_DIR / f"karaoke-{slug}.mp3"
    if out.exists() and kar.exists() and not force:
        return {"status": "EXISTS", "file": str(out), "karaoke": str(kar)}

    song = parse_lyric(lyric_path)
    if len(song["lyrics"]) > 3000:
        raise SystemExit(f"{slug}: lyrics {len(song['lyrics'])} chars > 3000 limit")

    clips: dict = {}
    flags: dict = {}
    before = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    COVER_DIR.mkdir(parents=True, exist_ok=True)
    raw = OUT_DIR / f"song-{slug}.m4a"
    rawext = OUT_DIR / f"song-{slug}-ext.m4a"
    extended = False

    with sync_playwright() as p:
        br, ctx = B.connect(p)
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

            # Only worth extending if the model came back short of the brief.
            since2 = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            flags["rate_limited"] = False
            ext = None
            if _seconds(raw) < MIN_SECONDS:
                try:
                    ext = _extend(page, base["id"], clips, since2,
                                  {base["id"]}, flags=flags)
                except Exception as exc:  # the panel is flaky; keep the base take
                    print(f"[warn] {slug}: extend failed: {exc}", file=sys.stderr)
            if ext:
                _download(page, ext, rawext)
                _cover(page, ext, COVER_DIR / f"cover-{slug}.jpg")
                extended = True
            elif flags.get("rate_limited"):
                raise B.RateLimited(slug)
            else:
                page.screenshot(path=str(ROOT / "work" / f"extfail-{slug}.png"))
                extended = False
        finally:
            # A failed run must not leave its tab behind: a dozen orphaned tabs
            # makes the next run's CDP calls time out.
            page.close()

    if not raw.exists() or raw.stat().st_size == 0:
        raise RuntimeError(f"{slug}: empty download")

    # Extend may return the whole song already lengthened, or only the appended
    # tail. Tell them apart by duration and join the tail when that is what came
    # back.
    source = raw
    if extended and rawext.exists() and rawext.stat().st_size:
        if _seconds(rawext) > _seconds(raw) + 5:
            source = rawext
        else:
            source = raw.with_name(f"{slug}-full.m4a")
            _join(raw, rawext, source)

    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(source),
         "-codec:a", "libmp3lame", "-qscale:a", "2", str(out)],
        check=True,
    )
    raw.unlink(missing_ok=True)
    rawext.unlink(missing_ok=True)

    # The clip id that ends up being the master is the one to split. This is a
    # plain read, so a throttle on generation does not affect it.
    master_id = (ext or base)["id"]
    stem_dir = OUT_DIR / f"stems-{slug}"
    with sync_playwright() as p2:
        br2, ctx2 = B.connect(p2)
        pg2 = ctx2.new_page()
        try:
            stems = _stems(pg2, master_id, stem_dir)
        finally:
            pg2.close()
    _karaoke(out, kar, stems=stems)
    dur = _seconds(out)
    return {"status": "CREATED", "file": str(out), "karaoke": str(kar),
            "seconds": round(dur, 1), "bytes": out.stat().st_size,
            "clip_id": base["id"], "extended": extended}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        for f in sorted(LYRICS_DIR.glob("*.txt")):
            print(f.stem)
        return 0
    if not args.slug:
        ap.error("need a slug (or --list)")
    try:
        r = generate(args.slug, force=args.force)
    except B.LoginRequired as exc:
        print(str(exc), file=sys.stderr)
        return 3
    except B.RateLimited:
        print(json.dumps({"status": "RATE_LIMITED", "slug": args.slug}))
        return 4
    print(json.dumps(r, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
