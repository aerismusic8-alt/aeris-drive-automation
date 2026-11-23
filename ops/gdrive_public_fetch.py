#!/usr/bin/env python3
"""Download a shared Google Drive folder without OAuth.

Why not the Drive API: the client behind `scripts/gdrive-auth.py` only accepts
non-sensitive scopes, so `drive` and `drive.readonly` are rejected at the device
code step (`invalid_scope`) and `drive.file` cannot see a file the user uploaded
by hand. Measured 2026-11-23. A folder shared "anyone with the link" needs no
token at all, which also means it survives a pod recycle with no session.

    python3 ops/gdrive_public_fetch.py "https://drive.google.com/drive/folders/<id>" --out work/refs
    python3 ops/gdrive_public_fetch.py <id> --out work/refs --only mp3 --max-mb 200

It reads the folder through `embeddedfolderview`, which lists name, id and size
per entry as plain HTML, then downloads each file. A file over Drive's virus-scan
threshold answers with a confirm page instead of bytes; the token from that page
is reused, which is the step most scrapers miss.
"""
from __future__ import annotations

import argparse
import html
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/140.0 Safari/537.36")
LIST_URL = "https://drive.google.com/embeddedfolderview?id={fid}#list"
FILE_URL = "https://drive.google.com/uc?export=download&id={fid}"


def _get(url: str, timeout: int = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()
    except urllib.error.HTTPError as exc:
        if exc.code in (403, 404):
            raise SystemExit(f"HTTP {exc.code}: folder is private, deleted, or the id is wrong") from None
        raise


def folder_id(text: str) -> str:
    m = re.search(r"/folders/([A-Za-z0-9_-]{10,})", text) or re.search(r"[?&]id=([A-Za-z0-9_-]{10,})", text)
    if m:
        return m.group(1)
    if re.fullmatch(r"[A-Za-z0-9_-]{10,}", text.strip()):
        return text.strip()
    raise SystemExit(f"cannot read a folder id from {text!r}")


def list_folder(fid: str) -> list[dict]:
    page = _get(LIST_URL.format(fid=fid)).decode("utf-8", "replace")
    if "flip-entry" not in page:
        raise SystemExit("folder is not publicly listable (share it as 'anyone with the link')")
    out = []
    for chunk in page.split('class="flip-entry"')[1:]:
        mid = re.search(r'id="entry-([A-Za-z0-9_-]+)"', chunk)
        mname = re.search(r'flip-entry-title">([^<]*)<', chunk)
        msize = re.search(r'flip-entry-size">([^<]*)<', chunk)
        if not mid or not mname:
            continue
        size = (msize.group(1) if msize else "").replace("\xa0", " ")
        out.append({"id": mid.group(1), "name": html.unescape(mname.group(1)),
                    "size": size.strip(), "folder": "folder" in chunk.lower()})
    return out


def download(fid: str, dest: Path, timeout: int = 600) -> int:
    data = _get(FILE_URL.format(fid=fid), timeout=timeout)
    if data[:2] == b"PK" or not data.lstrip().startswith(b"<"):
        dest.write_bytes(data)
        return len(data)
    # Confirm page for large files: carry its token into a second request.
    page = data.decode("utf-8", "replace")
    token = re.search(r'name="confirm" value="([^"]+)"', page)
    uuid = re.search(r'name="uuid" value="([^"]+)"', page)
    if token:
        q = {"id": fid, "export": "download", "confirm": token.group(1)}
        if uuid:
            q["uuid"] = uuid.group(1)
        data = _get("https://drive.google.com/uc?" + urllib.parse.urlencode(q), timeout=timeout)
    dest.write_bytes(data)
    return len(data)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("link")
    ap.add_argument("--out", default="work/refs")
    ap.add_argument("--only", default="", help="comma list of extensions to keep (default: all)")
    ap.add_argument("--max-mb", type=float, default=0, help="skip files larger than this")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--depth", type=int, default=1, help="how many subfolder levels to walk")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    keep = {e.strip().lower().lstrip(".") for e in args.only.split(",") if e.strip()}
    got = []

    def walk(fid: str, where: Path, depth: int) -> None:
        for e in list_folder(fid):
            if e["folder"]:
                if depth > 0:
                    sub = where / e["name"]
                    sub.mkdir(parents=True, exist_ok=True)
                    walk(e["id"], sub, depth - 1)
                continue
            ext = e["name"].rsplit(".", 1)[-1].lower() if "." in e["name"] else ""
            if keep and ext not in keep:
                continue
            if args.max_mb:
                m = re.search(r"([\d.]+)\s*MB", e["size"])
                if m and float(m.group(1)) > args.max_mb:
                    print(f"  skip {e['name']} ({e['size']})")
                    continue
            if args.limit and len(got) >= args.limit:
                return
            dest = where / e["name"]
            n = download(e["id"], dest)
            got.append((str(dest), n))
            print(f"  {n/1e6:8.1f} MB  {dest}")

    walk(folder_id(args.link), out, args.depth)
    print(f"\n{len(got)} file(s), {sum(n for _, n in got)/1e6:.1f} MB -> {out}")
    return 0 if got else 1


if __name__ == "__main__":
    raise SystemExit(main())
