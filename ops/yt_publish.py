#!/usr/bin/env python3
"""Upload an episode to one of the 4 channels.

  python3 ops/yt_publish.py --ch ch2 --video FILE --thumb FILE \
      --title "..." --desc-file DESC.txt --tags-file TAGS.txt [--schedule ISO] [--now]

Two facts learned the hard way (2026-10-24):
  * `videos.update` returns a bare Video resource, NOT {"items": [...]}. Parsing it
    as a list makes every success look like a failure.
  * Releasing a scheduled video early means setting privacyStatus=public AND
    clearing publishAt in the SAME update. Setting only one leaves it scheduled.
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import yt_auth  # noqa: E402

UPLOAD = "https://www.googleapis.com/upload/youtube/v3/videos"
THUMBS = "https://www.googleapis.com/upload/youtube/v3/thumbnails/set"


def multipart_upload(path, metadata, token, mime="video/mp4"):
    import urllib.request
    boundary = "axboundary" + str(int(time.time()))
    body = b""
    body += f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".encode()
    body += json.dumps(metadata, ensure_ascii=False).encode("utf-8")
    body += f"\r\n--{boundary}\r\nContent-Type: {mime}\r\n\r\n".encode()
    body += open(path, "rb").read()
    body += f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(
        f"{UPLOAD}?uploadType=multipart&part=snippet,status",
        data=body,
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": f"multipart/related; boundary={boundary}",
                 "Content-Length": str(len(body))},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=3600) as f:
            return f.status, json.loads(f.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode(errors="replace") or "{}")


def set_thumbnail(video_id, path, token):
    import urllib.request
    data = open(path, "rb").read()
    req = urllib.request.Request(
        f"{THUMBS}?videoId={video_id}", data=data,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "image/jpeg"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=300) as f:
            return f.status, json.loads(f.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode(errors="replace") or "{}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ch", required=True, choices=list(yt_auth.CHANNELS))
    ap.add_argument("--video", required=True)
    ap.add_argument("--thumb")
    ap.add_argument("--title", required=True)
    ap.add_argument("--desc-file", required=True)
    ap.add_argument("--tags-file")
    ap.add_argument("--category", default="27")  # 27 = Education
    ap.add_argument("--schedule", help="ISO8601 UTC, e.g. 2026-10-25T11:00:00Z")
    ap.add_argument("--now", action="store_true", help="publish immediately")
    ap.add_argument("--privacy", default="private")
    a = ap.parse_args()

    # Require a deliberate choice, but let an explicit --privacy count as one:
    # "private" is also the default, so the default alone must not be enough.
    explicit_privacy = "--privacy" in sys.argv
    if not (a.now or a.schedule or explicit_privacy):
        raise SystemExit("refusing to upload: pass --now, --schedule, or --privacy explicitly")

    tags = []
    if a.tags_file and os.path.exists(a.tags_file):
        tags = [t.strip() for t in open(a.tags_file, encoding="utf-8").read().split(",") if t.strip()]

    # videos.update REPLACES the parts you send. Omitting `embeddable` or
    # `publicStatsViewable` makes the API return them false, which silently
    # breaks embedding on every release-early update. Send the complete
    # writable status every time. (ops/yt_video_status.py repairs the fallout.)
    status = {
        "selfDeclaredMadeForKids": False,
        "license": "youtube",
        "embeddable": True,
        "publicStatsViewable": True,
    }
    if a.now:
        status["privacyStatus"] = "public"
    elif a.schedule:
        status["privacyStatus"] = "private"
        status["publishAt"] = a.schedule
    else:
        status["privacyStatus"] = a.privacy

    metadata = {
        "snippet": {
            "title": a.title[:100],
            "description": open(a.desc_file, encoding="utf-8").read()[:4900],
            "tags": tags[:30],
            "categoryId": a.category,
            "defaultLanguage": "th",
            "defaultAudioLanguage": "th",
        },
        "status": status,
    }

    tok = yt_auth.access_token(a.ch)
    print(f"uploading {os.path.basename(a.video)} ({os.path.getsize(a.video)/1e6:.1f} MB) to {a.ch}")
    code, body = multipart_upload(a.video, metadata, tok)
    print(f"HTTP {code}")
    if code not in (200, 201):
        print(json.dumps(body, ensure_ascii=False)[:800])
        raise SystemExit(1)
    vid = body["id"]
    print(f"video id {vid}  privacy {body['status']['privacyStatus']}  "
          f"publishAt {body['status'].get('publishAt', '-')}")
    if a.thumb:
        tc, tb = set_thumbnail(vid, a.thumb, tok)
        print(f"thumbnail HTTP {tc}")
    print(f"https://youtu.be/{vid}")


if __name__ == "__main__":
    main()
