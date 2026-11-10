#!/usr/bin/env python3
"""Free web search + page reading — the no-quota replacement for Tavily.

K (2026-11-09): "Tavily คืออะไร ใช้ย่อยแล้วโควต้าหมดตลอด ทำไมไม่หาอะไรมาแทน".
Tavily is a paid search API whose free tier has a hard monthly cap; when the
cap is hit every `tavily_search`/`tavily_extract` call fails with HTTP 432 and
the agent is blind. This module is the free answer, so that never happens:

  * search  -> DuckDuckGo (the `ddgs` package). No key, no account, no quota.
  * read    -> `trafilatura` fetches and extracts the readable text of a page.

Both are ordinary pip packages, so there is nothing to sign up for and nothing
to run out of. Fallbacks are tried in order: if one backend is rate-limited for
a moment, the next answers; if all text backends fail, a Wikipedia lookup is
still available.

    python3 ops/websearch.py "UNHEARD MUSIC ไม่มีใครรู้ตัวเรา"
    python3 ops/websearch.py --read https://example.com/page
    python3 ops/websearch.py --json "free AI singing voice generator"
    python3 ops/websearch.py --read --max-chars 2000 https://example.com
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request


def _ddg(query: str, n: int) -> list[dict]:
    from ddgs import DDGS

    out: list[dict] = []
    last = None
    # DuckDuckGo occasionally answers an empty page (rate limit); a short retry
    # with a fresh backend list almost always gets a result, and it costs
    # nothing, so a single empty answer must not end the search.
    for backend in ("auto", "html", "lite"):
        try:
            for r in DDGS().text(query, max_results=n, backend=backend):
                out.append({
                    "title": r.get("title", ""),
                    "url": r.get("href") or r.get("url", ""),
                    "snippet": r.get("body", ""),
                })
            if out:
                return out
        except Exception as e:  # noqa: BLE001
            last = e
    if last and not out:
        raise last
    return out


def _wikipedia(query: str, n: int) -> list[dict]:
    """Last-resort backend: the MediaWiki search API, keyless and quota-free."""
    api = ("https://en.wikipedia.org/w/api.php?action=query&list=search"
           "&format=json&srlimit={n}&srsearch={q}")
    url = api.format(n=n, q=urllib.parse.quote(query))
    req = urllib.request.Request(url, headers={"User-Agent": "ax-websearch/1.0"})
    with urllib.request.urlopen(req, timeout=30) as f:
        data = json.loads(f.read().decode())
    hits = data.get("query", {}).get("search", [])
    return [{
        "title": h.get("title", ""),
        "url": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(h["title"].replace(" ", "_")),
        "snippet": (h.get("snippet", "") or "").replace('<span class="searchmatch">', "").replace("</span>", ""),
    } for h in hits]


def search(query: str, n: int = 8) -> list[dict]:
    """Search the web for free. Tries DuckDuckGo, then Wikipedia."""
    errors = []
    for backend, fn in (("ddgs", _ddg), ("wikipedia", _wikipedia)):
        try:
            hits = fn(query, n)
            if hits:
                return hits
            errors.append(f"{backend}: no results")
        except Exception as e:  # noqa: BLE001 — any backend failure falls through
            errors.append(f"{backend}: {type(e).__name__}: {e}")
    raise RuntimeError("all search backends failed: " + "; ".join(errors))


def read(url: str, max_chars: int = 6000) -> str:
    """Fetch a page and return its readable text (no key, no quota)."""
    import trafilatura

    downloaded = trafilatura.fetch_url(url)
    text = trafilatura.extract(downloaded) if downloaded else None
    if not text:
        # trafilatura can be strict; fall back to a plain fetch + tag strip.
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=40) as f:
            raw = f.read().decode("utf-8", errors="ignore")
        text = trafilatura.extract(raw, url=url) or raw
    text = (text or "").strip()
    return text[:max_chars]


def _print_hits(hits: list[dict]) -> None:
    for i, h in enumerate(hits, 1):
        print(f"{i}. {h['title']}")
        print(f"   {h['url']}")
        if h.get("snippet"):
            print(f"   {h['snippet']}")
        print()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="free web search + reader (no quota)")
    ap.add_argument("query", nargs="*", help="search query")
    ap.add_argument("--read", metavar="URL", help="read a page instead of searching")
    ap.add_argument("--json", action="store_true", help="emit JSON")
    ap.add_argument("-n", "--num", type=int, default=8)
    ap.add_argument("--max-chars", type=int, default=6000)
    args = ap.parse_args(argv)

    if args.read:
        text = read(args.read, args.max_chars)
        if args.json:
            print(json.dumps({"url": args.read, "text": text}, ensure_ascii=False))
        else:
            print(text)
        return 0

    query = " ".join(args.query).strip()
    if not query:
        ap.error("give a query, or --read URL")
    hits = search(query, args.num)
    if args.json:
        print(json.dumps(hits, ensure_ascii=False, indent=2))
    else:
        _print_hits(hits)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
