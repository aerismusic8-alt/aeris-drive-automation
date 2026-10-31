#!/usr/bin/env python3
"""Upload files to Google Drive with the refresh token from gdrive-auth.py.

No browser, no interactive login, no rclone. The token is read from the
`GDRIVE_REFRESH_TOKEN` secret (or the state file), so this runs the same way in
this chat, in a brand new chat, in a recycled pod, or on another machine.

    python3 scripts/gdrive-upload.py --check
    python3 scripts/gdrive-upload.py FILE... --folder "AX Content Lab/aeris938-1"
    python3 scripts/gdrive-upload.py --dir aeris938-1/library --folder "AX Content Lab/aeris938-1"

A file that already exists with the same name and size is skipped, so re-running
a batch is safe and cheap.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

STATE = Path(os.environ.get("AERIS_STATE_DIR", "/workspace/ax-tools/aeris938-state"))
TOKEN_FILE = STATE / "gdrive-refresh-token.txt"
CLIENT_FILE = STATE / "gdrive-client.json"
API = "https://www.googleapis.com/drive/v3"
UPLOAD = "https://www.googleapis.com/upload/drive/v3/files"


def refresh_token() -> str:
    token = os.environ.get("GDRIVE_REFRESH_TOKEN")
    if not token and TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text().strip()
    if not token:
        raise SystemExit(
            "no GDRIVE_REFRESH_TOKEN (and no state file). Run scripts/gdrive-auth.py start")
    return token


def client() -> tuple[str, str]:
    """OAuth client id/secret, from the environment or the state file.

    Outside OpenHands (PC1, a laptop) there is no secret injection, so the pair is
    also read from `<state>/gdrive-client.json`; otherwise a valid token fails
    with a misleading "client id is not set".
    """
    cid = os.environ.get("GDRIVE_CLIENT_ID") or os.environ.get("YT_CLIENT_ID")
    csec = os.environ.get("GDRIVE_CLIENT_SECRET") or os.environ.get("YT_CLIENT_SECRET")
    if not (cid and csec) and CLIENT_FILE.exists():
        try:
            data = json.loads(CLIENT_FILE.read_text())
            cid = cid or data.get("client_id")
            csec = csec or data.get("client_secret")
        except (OSError, ValueError):
            pass
    if not cid or not csec:
        raise SystemExit(
            "OAuth client not configured. Set GDRIVE_CLIENT_ID / GDRIVE_CLIENT_SECRET "
            f"(or YT_CLIENT_ID / YT_CLIENT_SECRET), or write {CLIENT_FILE}")
    return cid, csec


def access_token() -> str:
    cid, csec = client()
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=urllib.parse.urlencode({
            "client_id": cid, "client_secret": csec,
            "refresh_token": refresh_token(), "grant_type": "refresh_token",
        }).encode(),
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=30) as f:
            return json.load(f)["access_token"]
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"token refresh failed: {exc.code} {exc.read().decode()[:200]}")


class Drive:
    def __init__(self, at: str):
        self.at = at

    def _req(self, method: str, url: str, body: bytes | None = None,
             ctype: str = "application/json") -> dict:
        req = urllib.request.Request(url, method=method, data=body,
                                     headers={"Authorization": f"Bearer {self.at}",
                                              "Content-Type": ctype})
        try:
            with urllib.request.urlopen(req, timeout=300) as f:
                raw = f.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode()[:300]
            raise SystemExit(f"drive {method} {url} -> {exc.code}: {detail}")

    def find_folder(self, path: str) -> str:
        """Resolve 'A/B/C' to a folder id, creating what does not exist."""
        parent = "root"
        for part in [p for p in path.split("/") if p]:
            q = (f"name = '{part}' and mimeType = 'application/vnd.google-apps.folder' "
                 f"and '{parent}' in parents and trashed = false")
            url = f"{API}/files?q={urllib.parse.quote(q)}&fields=files(id,name)&supportsAllDrives=true"
            found = self._req("GET", url).get("files", [])
            if found:
                parent = found[0]["id"]
            else:
                body = json.dumps({"name": part, "mimeType": "application/vnd.google-apps.folder",
                                   "parents": [parent]}).encode()
                parent = self._req("POST", f"{API}/files?fields=id", body)["id"]
        return parent

    def existing(self, name: str, folder: str, size: int) -> dict | None:
        q = f"name = '{name}' and '{folder}' in parents and trashed = false"
        url = f"{API}/files?q={urllib.parse.quote(q)}&fields=files(id,name,size)"
        for f in self._req("GET", url).get("files", []):
            if int(f.get("size", -1)) == size:
                return f
        return None

    def upload(self, path: Path, folder: str) -> dict:
        size = path.stat().st_size
        have = self.existing(path.name, folder, size)
        if have:
            return {"name": path.name, "id": have["id"], "skipped": True}
        ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        meta = json.dumps({"name": path.name, "parents": [folder]}).encode()
        boundary = "axuploadboundary"
        pre = (f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
               ).encode() + meta + f"\r\n--{boundary}\r\nContent-Type: {ctype}\r\n\r\n".encode()
        post = f"\r\n--{boundary}--\r\n".encode()
        body = pre + path.read_bytes() + post
        url = f"{UPLOAD}?uploadType=multipart&fields=id,name,size,webViewLink"
        return self._req("POST", url, body, f"multipart/related; boundary={boundary}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="files to upload")
    ap.add_argument("--dir", action="append", default=[], help="upload every file under this dir")
    ap.add_argument("--folder", default="AX Content Lab", help="Drive folder path to upload into")
    ap.add_argument("--check", action="store_true",
                    help="prove the credential works (no Drive API call), then exit")
    args = ap.parse_args()

    if args.check:
        # Deliberately NOT a Drive API call: the API is disabled in the Cloud
        # project that owns this OAuth client, so /about answers 403 and would
        # read as "your token is broken" when it is not. Only the token endpoint
        # is exercised, which is what the credential's health actually depends on.
        tok = refresh_token()
        access_token()  # exercises the refresh, raising on a bad credential
        print("TOKEN OK")
        print(f"  length  : {len(tok)} chars")
        print(f"  source  : {'secret GDRIVE_REFRESH_TOKEN' if os.environ.get('GDRIVE_REFRESH_TOKEN') else TOKEN_FILE}")
        print("  The credential works. Drive API calls will 403 until the API is")
        print("  enabled in the owning Cloud project; the browser uploader needs no API.")
        return 0

    drv = Drive(access_token())

    targets: list[Path] = [Path(f) for f in args.files]
    for d in args.dir:
        targets += sorted(p for p in Path(d).rglob("*") if p.is_file())
    if not targets:
        print("nothing to upload (pass files or --dir)", file=sys.stderr)
        return 1

    folder_id = drv.find_folder(args.folder)
    print(f"folder: {args.folder} (id {folder_id})")
    done = skipped = 0
    for p in targets:
        res = drv.upload(p, folder_id)
        if res.get("skipped"):
            skipped += 1
            print(f"  skip  {p}  (already there, {res['id']})")
        else:
            done += 1
            print(f"  up    {p}  -> {res.get('webViewLink', res.get('id'))}")
    print(f"uploaded={done} skipped={skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
