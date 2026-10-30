#!/usr/bin/env python3
"""Read and update YouTube channel branding (name, description, keywords, language).

  python3 ops/yt_branding.py read                 # all 4 channels, current state
  python3 ops/yt_branding.py read ch2
  python3 ops/yt_branding.py plan                 # what the proposal would change
  python3 ops/yt_branding.py apply ch2 --dry-run  # show the exact payload
  python3 ops/yt_branding.py apply ch2            # write it

`channels.update` replaces the parts you send. We always send the COMPLETE
brandingSettings.channel object (title + description + keywords + language +
country), because omitting a field clears it. Sending only `keywords` wipes the
description. That is the trap this module exists to avoid.

Verified 2026-10-24: all 4 refresh tokens carry the full
`https://www.googleapis.com/auth/youtube` scope, so branding writes are allowed.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import yt_auth  # noqa: E402

PROPOSAL = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "channel_branding.json")


def read(ch):
    tok = yt_auth.access_token(ch)
    st, body = yt_auth.api_get("channels", tok,
                               part="brandingSettings,snippet,statistics", mine="true")
    if st != 200:
        raise SystemExit(f"{ch} read failed: {st} {body}")
    it = body["items"][0]
    chb = it.get("brandingSettings", {}).get("channel", {})
    return {
        "channel": ch,
        "id": it["id"],
        "handle_title": it["snippet"]["title"],
        "title": chb.get("title") or it["snippet"]["title"],
        "description": chb.get("description") or "",
        "keywords": chb.get("keywords") or "",
        "defaultLanguage": chb.get("defaultLanguage"),
        "country": chb.get("country"),
        "subs": it["statistics"].get("subscriberCount"),
        "videos": it["statistics"].get("videoCount"),
    }


def cmd_read(args):
    only = args[0] if args and not args[0].startswith("-") else None
    for ch in yt_auth.CHANNELS:
        if only and ch != only:
            continue
        d = read(ch)
        print(f"=== {d['channel']}  {d['id']}  subs={d['subs']} videos={d['videos']}")
        print(f"  title       : {d['title']}")
        print(f"  language    : {d['defaultLanguage']}   country: {d['country']}")
        print(f"  keywords    : {d['keywords'] or '(EMPTY)'}")
        print(f"  description : {d['description'][:160].replace(chr(10), ' / ') or '(EMPTY)'}")
        print()


def _full_payload(current, new):
    """Build a COMPLETE channel object so no field is silently cleared."""
    return {
        "id": current["id"],
        "brandingSettings": {
            "channel": {
                "title": new.get("title", current["title"]),
                "description": new.get("description", current["description"]),
                "keywords": new.get("keywords", current["keywords"]),
                "defaultLanguage": new.get("defaultLanguage", current["defaultLanguage"]),
                "country": new.get("country", current["country"]),
            }
        },
    }


def cmd_apply(args):
    ch = args[0]
    dry = "--dry-run" in args
    proposal = json.load(open(PROPOSAL, encoding="utf-8"))
    if ch not in proposal:
        raise SystemExit(f"no proposal for {ch} in {PROPOSAL}")
    new = proposal[ch]
    current = read(ch)
    payload = _full_payload(current, new)

    print(f"--- {ch} ({current['id']})")
    for field in ("title", "defaultLanguage", "country"):
        old, nw = current[field], payload["brandingSettings"]["channel"][field]
        flag = "  <-- CHANGE" if old != nw else ""
        print(f"  {field:16s}: {old!r} -> {nw!r}{flag}")
    for field in ("description", "keywords"):
        old = current[field] or ""
        nw = payload["brandingSettings"]["channel"][field] or ""
        if old.strip() == nw.strip():
            print(f"  {field:16s}: unchanged")
        else:
            print(f"  {field:16s}: CHANGED ({len(old)} -> {len(nw)} chars)")
    if dry:
        print("\nDRY RUN - nothing written. Payload:")
        print(json.dumps(payload, ensure_ascii=False, indent=2)[:1500])
        return

    tok = yt_auth.access_token(ch)
    # MUST be PUT. This sandbox sits behind a proxy that answers POST/PATCH to
    # www.googleapis.com with a bare 404 (Server: scaffolding on HTTPServer2), which
    # looks exactly like a wrong URL. GET and PUT pass through to the real API.
    # `channels.update` is PUT in the YouTube API, so this is the correct verb anyway.
    st, body = yt_auth.api_request("channels", tok, payload, method="PUT",
                                   part="brandingSettings")
    print(f"\nHTTP {st}")
    if st not in (200, 201):
        print(json.dumps(body, ensure_ascii=False)[:800])
        raise SystemExit(1)
    after = read(ch)
    print(f"verify title={after['title']!r} language={after['defaultLanguage']} "
          f"keywords={'yes' if after['keywords'] else 'EMPTY'}")


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return
    if a[0] == "read":
        cmd_read(a[1:])
    elif a[0] == "plan":
        proposal = json.load(open(PROPOSAL, encoding="utf-8"))
        for ch in yt_auth.CHANNELS:
            cur = read(ch)
            new = proposal.get(ch, {})
            changes = [f for f in ("title", "description", "keywords", "defaultLanguage", "country")
                       if f in new and (cur.get(f) or "") != (new.get(f) or "")]
            print(f"{ch} {cur['title']!r}: would change {changes or 'nothing'}")
    elif a[0] == "apply":
        cmd_apply(a[1:])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
