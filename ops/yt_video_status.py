#!/usr/bin/env python3
"""Audit and repair per-video status flags on the 4 channels.

Why this exists
---------------
`videos.update` REPLACES the parts you send, exactly like `channels.update`.
Our early-release code sent only `privacyStatus` (and `publishAt`), so every
video it released came back with `embeddable: false` and
`publicStatsViewable: false` — the API's defaults for a field you omit in a
PUT. A non-embeddable video cannot be played on any site that embeds YouTube.

Measured 2026-10-24: 8 of 76 ch1 videos and 10 of 12 ch2 videos were affected,
and every one of them had been through the release-early update.

Usage
-----
  python3 ops/yt_video_status.py audit            # who is broken
  python3 ops/yt_video_status.py restore          # send the COMPLETE status
  python3 ops/yt_video_status.py restore --dry-run
  python3 ops/yt_video_status.py restore --ch ch2
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import yt_auth  # noqa: E402

# The writable half of the status object. Send all of it, or the fields you
# leave out come back false. `uploadStatus`/`failureReason`/`rejectionReason`
# are read-only and must not be sent.
def wanted_status(v):
    st = v["status"]
    out = {
        "privacyStatus": st.get("privacyStatus", "private"),
        "license": st.get("license", "youtube"),
        "embeddable": True,
        "publicStatsViewable": True,
        "selfDeclaredMadeForKids": st.get("selfDeclaredMadeForKids", False),
    }
    if st.get("publishAt"):
        out["publishAt"] = st["publishAt"]
    return out


def broken(v):
    st = v["status"]
    return (not st.get("embeddable")) or (not st.get("publicStatsViewable"))


def fetch_status(ch, tok):
    ids = yt_auth.all_upload_ids(tok)
    rows = []
    for k in range(0, len(ids), 50):
        for attempt in range(4):
            code, body = yt_auth.api_get(
                "videos", tok, part="status,snippet", id=",".join(ids[k:k + 50]))
            if "items" in body:
                break
            time.sleep(3)
        rows += body.get("items", [])
    return rows


def cmd_audit(args):
    for ch in args.ch:
        tok = yt_auth.access_token(ch)
        rows = fetch_status(ch, tok)
        bad = [v for v in rows if broken(v)]
        print(f"{ch}: {len(bad)} of {len(rows)} videos with embedding/stats OFF")
        for v in sorted(bad, key=lambda x: x["snippet"]["publishedAt"]):
            s = v["status"]
            print("  ", v["snippet"]["publishedAt"][:16], s.get("privacyStatus"),
                  "emb=", s.get("embeddable"), "stats=", s.get("publicStatsViewable"),
                  v["id"], v["snippet"]["title"][:48])


def cmd_restore(args):
    for ch in args.ch:
        tok = yt_auth.access_token(ch)
        rows = fetch_status(ch, tok)
        bad = [v for v in rows if broken(v)]
        if not bad:
            print(f"{ch}: nothing to repair")
            continue
        print(f"{ch}: repairing {len(bad)} video(s)"
              + (" [dry-run]" if args.dry_run else ""))
        for v in sorted(bad, key=lambda x: x["snippet"]["publishedAt"]):
            st = wanted_status(v)
            if args.dry_run:
                print("   would send", v["id"], st)
                continue
            code, body = yt_auth.api_request(
                "videos", tok, {"id": v["id"], "status": st}, part="status")
            got = body.get("status", {}) if isinstance(body, dict) else {}
            ok = got.get("embeddable") is True and got.get("publicStatsViewable") is True
            print(f"   {v['id']} HTTP {code} emb={got.get('embeddable')} "
                  f"stats={got.get('publicStatsViewable')} "
                  f"privacy={got.get('privacyStatus')} "
                  f"{'OK' if ok else 'CHECK'} {v['snippet']['title'][:40]}")
            time.sleep(0.4)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["audit", "restore"])
    ap.add_argument("--ch", nargs="*", default=list(yt_auth.CHANNELS))
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    (cmd_audit if a.cmd == "audit" else cmd_restore)(a)


if __name__ == "__main__":
    main()
