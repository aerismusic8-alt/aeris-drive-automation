#!/usr/bin/env python3
"""YouTube OAuth rail for the 4 AKATH channels.

Tokens are account-scoped OpenHands secrets injected as env vars in this session:
  YT_CLIENT_ID / YT_CLIENT_SECRET
  YT_CH1_REFRESH_TOKEN .. YT_CH4_REFRESH_TOKEN

Usage:
  python3 ops/yt_auth.py whoami            # id, title, subs, video count per channel
  python3 ops/yt_auth.py whoami --ch ch2
  python3 ops/yt_auth.py token ch2         # print an access token (short lived)
  python3 ops/yt_auth.py videos ch2        # newest uploads with privacy status
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOKEN_URL = "https://oauth2.googleapis.com/token"
API = "https://www.googleapis.com/youtube/v3"

CHANNELS = {
    "ch1": ("YT_CH1_REFRESH_TOKEN", "ตาต้า GenX Shop"),
    "ch2": ("YT_CH2_REFRESH_TOKEN", "Farmmer"),
    "ch3": ("YT_CH3_REFRESH_TOKEN", "AERIS Music"),
    "ch4": ("YT_CH4_REFRESH_TOKEN", "kongkeat pratumma"),
}


def _request(url, data=None, headers=None, method=None, timeout=120):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as f:
                return f.status, json.loads(f.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            # 429 / 5xx are retryable; everything else is a real answer.
            if e.code in (429, 500, 502, 503, 504) and attempt < 5:
                time.sleep(2 * (attempt + 1) ** 2)
                continue
            try:
                return e.code, json.loads(body)
            except Exception:
                return e.code, {"raw": body}
    raise RuntimeError("unreachable")


def access_token(ch, timeout=60):
    var = CHANNELS[ch][0]
    rt = os.environ.get(var)
    if not rt:
        raise SystemExit(f"{var} is not set in this session")
    data = urllib.parse.urlencode({
        "client_id": os.environ["YT_CLIENT_ID"],
        "client_secret": os.environ["YT_CLIENT_SECRET"],
        "refresh_token": rt,
        "grant_type": "refresh_token",
    }).encode()
    status, body = _request(TOKEN_URL, data=data, timeout=timeout)
    if "access_token" not in body:
        raise SystemExit(f"{ch} token refresh failed: {status} {body}")
    return body["access_token"]


def api_get(path, token, **params):
    url = f"{API}/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    return _request(url, headers={"Authorization": f"Bearer {token}"})


def api_post_json(path, token, payload, **params):
    url = f"{API}/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    return _request(url, data=json.dumps(payload).encode(),
                    headers={"Authorization": f"Bearer {token}",
                             "Content-Type": "application/json"}, method="POST")


def api_request(path, token, payload, method="PUT", **params):
    """Generic write helper.

    This sandbox is behind a proxy that returns a bare 404
    (Server: scaffolding on HTTPServer2) for POST and PATCH to www.googleapis.com,
    while GET and PUT reach the real API. Anything that updates a resource must use
    PUT for that reason. Uploads are unaffected: they go to
    www.googleapis.com/upload, which is served by UploadServer.
    """
    url = f"{API}/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    return _request(url, data=json.dumps(payload).encode(),
                    headers={"Authorization": f"Bearer {token}",
                             "Content-Type": "application/json"}, method=method)


def uploads_playlist(token):
    st, body = api_get("channels", token, part="contentDetails", mine="true")
    return body["items"][0]["contentDetails"]["relatedPlaylists"]["uploads"]


def all_upload_ids(token, cap=500):
    pl = uploads_playlist(token)
    ids, page = [], None
    while len(ids) < cap:
        st, body = api_get("playlistItems", token, part="contentDetails",
                           playlistId=pl, maxResults=50, **({"pageToken": page} if page else {}))
        ids += [i["contentDetails"]["videoId"] for i in body.get("items", [])]
        page = body.get("nextPageToken")
        if not page:
            break
    return ids


def cmd_whoami(args):
    only = args[args.index("--ch") + 1] if "--ch" in args else None
    for ch in CHANNELS:
        if only and ch != only:
            continue
        try:
            tok = access_token(ch)
            st, body = api_get("channels", tok, part="snippet,statistics", mine="true")
            it = body["items"][0]
            s = it["statistics"]
            print(f"{ch} {it['id']} {it['snippet']['title']!r} "
                  f"subs={s.get('subscriberCount')} videos={s.get('videoCount')}")
        except SystemExit as e:
            print(f"{ch} ERROR {e}")


def cmd_videos(args):
    ch = args[0] if args and not args[0].startswith("-") else "ch1"
    tok = access_token(ch)
    ids = all_upload_ids(tok)
    print(f"{ch}: {len(ids)} uploads")
    for k in range(0, len(ids), 50):
        st, body = api_get("videos", tok, part="status,contentDetails,snippet",
                           id=",".join(ids[k:k + 50]))
        for v in body.get("items", []):
            print("  ", v["status"]["privacyStatus"], v["status"].get("publishAt", "-"),
                  v["contentDetails"]["duration"], v["snippet"]["publishedAt"][:10],
                  v["snippet"]["title"][:60])


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    cmd, rest = args[0], args[1:]
    if cmd == "whoami":
        cmd_whoami(rest)
    elif cmd == "token":
        print(access_token(rest[0]))
    elif cmd == "videos":
        cmd_videos(rest)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
