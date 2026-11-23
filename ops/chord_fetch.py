#!/usr/bin/env python3
"""Fetch the words AND the chords of a hit song, then measure the craft.

K (2026-11-23): "เนื้อเพลง พร้อมคอร์ด ไปหาในเน็ตได้เยอะเลย" — the lyrics and the
chords are both on the web, so read them instead of guessing from the audio.

How it gets there, and why this route:

- Search engines are not usable from this sandbox. DuckDuckGo serves a CAPTCHA to
  curl *and* to the browser, Bing returns unrelated results, searx.be and
  r.jina.ai both demand verification, and api.lyrics.ovh/genius have no Thai
  coverage. Three sites were probed that do work keyless.
- guitarthai.com has a plain HTML search (`/chords/Search/song/<title>`) that
  returns song id, title and artist — but its chart is an image.
- The image is a chord chart: chords on one line, the lyric under them. Tesseract
  with the Thai pack reads it well enough to recover both. Chord symbols are Latin
  so they come out clean; Thai lyric text is good but not perfect.

So: search -> chart image -> OCR -> parse. The output is a shape profile — the
chord loop a hit actually repeats, chords per line, syllables per line, and the
section order — never a copy of the lyric.

Dependencies (free, and an apt install does NOT survive a pod recycle):
    sudo apt-get update && sudo apt-get install -y tesseract-ocr tesseract-ocr-tha

    python3 ops/chord_fetch.py --song "ไม่เอาคืน" --artist "ดัง พันกร"
    python3 ops/chord_fetch.py --list work/refs-songs.txt --out work/chords.json
"""
from __future__ import annotations

import argparse
import json
import re
import statistics as st
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

BASE = "https://www.guitarthai.com"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")

CHORD_RE = re.compile(
    r"^[A-G][#b]?(?:m|maj|min|sus|dim|aug|add|M)?\d{0,2}(?:/[A-G][#b]?)?$")
SECTION_RE = re.compile(r"^(INTRO|INSTRU|SOLO|OUTRO|ENDING|D\.S\.|\*+)")


def _get(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Referer": BASE + "/"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def search(title: str, artist: str | None = None) -> list[dict]:
    """Ask the site's own search; it returns id, title and artist per row."""
    html = _get(f"{BASE}/chords/Search/song/{urllib.parse.quote(title)}").decode(
        "utf-8", "ignore")
    rows = []
    for tr in re.findall(r"(?s)<tr>(.*?)</tr>", html):
        m = re.search(r'/chords/Song/(\d+)/"', tr)
        if not m:
            continue
        cells = [re.sub(r"<[^>]+>", "", c).strip()
                 for c in re.findall(r"(?s)<td[^>]*>(.*?)</td>", tr)]
        if len(cells) < 3:
            continue
        rows.append({"id": int(m.group(1)), "title": cells[1], "artist": cells[2]})
    # A one-word title ("รอ") matches half the catalogue, so the title must be
    # exact first and the artist second, never a fuzzy blend of the two.
    want = re.sub(r"\s+", "", title).lower()
    same_title = [r for r in rows if re.sub(r"\s+", "", r["title"]).lower() == want]
    if same_title:
        rows = same_title
    if artist:
        key = re.sub(r"\s+", "", artist).lower()
        exact = [r for r in rows if key in re.sub(r"\s+", "", r["artist"]).lower()]
        rows = exact + [r for r in rows if r not in exact]
    return rows


def chart_text(song_id: int) -> str:
    """The chord chart is a PNG; OCR it with the Thai pack."""
    png = _get(f"{BASE}/chords/files/{song_id}.png")
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as fh:
        fh.write(png)
        path = fh.name
    try:
        out = subprocess.run(["tesseract", path, "stdout", "-l", "tha+eng"],
                             capture_output=True, text=True, timeout=180)
    except FileNotFoundError:
        raise SystemExit("tesseract is not installed: sudo apt-get install -y "
                         "tesseract-ocr tesseract-ocr-tha")
    if out.returncode != 0:
        raise SystemExit(f"tesseract failed: {out.stderr[:200]}")
    return out.stdout


def _chords(line: str) -> list[str]:
    """Chord symbols carry Latin letters, so they can be read off any line.

    The chart writes a run as `INTRO /E/C#m/A/E/`, so `/` is a separator, not
    part of the symbol.
    """
    toks = [t.strip("()[],.:;") for t in re.split(r"[\s/|]+", line)]
    return [t for t in toks if CHORD_RE.match(t)]


def parse(text: str) -> dict:
    """Split the chart into chord runs, lyric lines and section markers."""
    chords: list[str] = []
    lyrics: list[str] = []
    sections: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if SECTION_RE.match(line):
            sections.append(line[:40])
        found = _chords(line)
        chords.extend(found)
        thai = len(re.findall(r"[\u0E00-\u0E7F]", line))
        if thai >= 4:
            # A chart packs several phrases on one visual line; two spaces is
            # where the singer breathes, so that is the line the ear hears.
            for part in re.split(r"\s{2,}", line):
                if len(re.findall(r"[\u0E00-\u0E7F]", part)) >= 4:
                    lyrics.append(part.strip())
    return {"chords": chords, "lyrics": lyrics, "sections": sections}


def _syllables(line: str) -> int:
    from pythainlp.tokenize import syllable_tokenize
    text = "".join(ch for ch in line if "\u0E00" <= ch <= "\u0E7F" or ch.isspace())
    return len([s for s in syllable_tokenize(text.strip()) if s.strip()]) if text.strip() else 0


def bar_loop(chords: list[str]) -> dict:
    """The four-chord bar loop, which is the unit a songwriter actually reuses."""
    for d in loop(chords, 8):
        if d["len"] == 4:
            return d
    return {}


def loop(chords: list[str], max_n: int = 8) -> list[dict]:
    """The progression a song actually repeats, as an n-gram count."""
    best: list[dict] = []
    for n in range(2, max_n + 1):
        counts = Counter(tuple(chords[i:i + n]) for i in range(len(chords) - n + 1))
        if not counts:
            continue
        seq, times = counts.most_common(1)[0]
        # Longer loops that repeat as often are the more useful finding.
        best.append({"len": n, "loop": list(seq), "times": times})
    return sorted(best, key=lambda d: (-d["times"], -d["len"]))[:3]


def measure(title: str, artist: str | None) -> dict:
    hits = search(title, artist)
    if not hits:
        raise SystemExit(f"no song found for {title!r}")
    hit = hits[0]
    text = chart_text(hit["id"])
    p = parse(text)
    syl = [s for s in (_syllables(l) for l in p["lyrics"]) if s]
    return {
        "query": {"title": title, "artist": artist},
        "matched": hit,
        "chart_url": f"{BASE}/chords/files/{hit['id']}.png",
        "lines": len(p["lyrics"]),
        "syllables_median": int(st.median(syl)) if syl else 0,
        "syllables_p10_p90": ([int(sorted(syl)[len(syl) // 10]),
                               int(sorted(syl)[min(len(syl) - 1, len(syl) * 9 // 10)])]
                              if syl else [0, 0]),
        "chord_count": len(p["chords"]),
        "chords_per_line": round(len(p["chords"]) / max(1, len(p["lyrics"])), 2),
        "chord_vocabulary": sorted(set(p["chords"])),
        "loops": loop(p["chords"]),
        "bar_loop": bar_loop(p["chords"]),
        "sections": p["sections"],
        "ocr_lines": p["lyrics"][:3],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--song")
    ap.add_argument("--artist")
    ap.add_argument("--list", help="file of 'title | artist' lines")
    ap.add_argument("--out")
    args = ap.parse_args()

    jobs = []
    if args.song:
        jobs.append((args.song, args.artist))
    if args.list:
        for ln in Path(args.list).read_text(encoding="utf-8").splitlines():
            if ln.strip() and not ln.startswith("#"):
                t, _, a = ln.partition("|")
                jobs.append((t.strip(), a.strip() or None))
    if not jobs:
        raise SystemExit("give --song or --list")

    rows = []
    for title, artist in jobs:
        try:
            r = measure(title, artist)
        except SystemExit as exc:
            print(f"  SKIP {title}: {exc}", file=sys.stderr)
            continue
        rows.append(r)
        top = r["loops"][0] if r["loops"] else {}
        print(f"  {r['matched']['title'][:22]:24s} {r['syllables_median']:2d} syl/line  "
              f"{r['chord_count']:3d} chords  loop "
              f"{'-'.join(top.get('loop', []))[:34]} x{top.get('times', 0)}")
        sys.stdout.flush()

    if rows and args.out:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({"songs": rows}, ensure_ascii=False, indent=2),
                       encoding="utf-8")
        print("written:", out)
    return 0 if rows else 1


if __name__ == "__main__":
    raise SystemExit(main())
