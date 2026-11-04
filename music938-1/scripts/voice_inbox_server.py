#!/usr/bin/env python3
"""Phone-friendly upload page so K can hand over an audio file.

The pod has no other inbound route for a local file: the Drive API is disabled
in the owning Cloud project, the chat message carried no attachment, and PC1 is
a separate machine. So the pod serves its own upload form on the public work
host and K opens it on a phone.

    python3 scripts/voice_inbox_server.py [port]   # default 12001

Uploads land in music938-1/voice-inbox/. Audio extensions only, capped in size.
This is a temporary door: stop it once the file has arrived.
"""
from __future__ import annotations

import email
import html
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INBOX = ROOT / "voice-inbox"
INBOX.mkdir(exist_ok=True)

AUDIO_EXT = {".wav", ".mp3", ".m4a", ".aac", ".ogg", ".opus", ".flac", ".webm"}
MAX_BYTES = 60 * 1024 * 1024

PAGE = """<!doctype html><html lang="th"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ส่งไฟล์เสียงนักร้อง — AERIS Music</title>
<style>
body{{font-family:system-ui,'Noto Sans Thai',sans-serif;margin:0;background:#0f1116;color:#e8e8ee}}
main{{max-width:520px;margin:0 auto;padding:24px}}
h1{{font-size:20px;margin:0 0 4px}} p{{color:#9aa0ad;font-size:14px;line-height:1.6}}
form{{margin:20px 0;padding:18px;background:#171a22;border:1px solid #262a35;border-radius:14px}}
input[type=file]{{width:100%;padding:12px;background:#0f1116;border:1px dashed #3a3f4d;border-radius:10px;color:#e8e8ee}}
button{{margin-top:14px;width:100%;padding:14px;font-size:16px;font-weight:600;color:#0f1116;background:#7ee0b0;border:0;border-radius:10px}}
.ok{{padding:12px;background:#14301f;border:1px solid #2c6b45;border-radius:10px;color:#a8f0c8}}
ul{{list-style:none;padding:0}} li{{padding:8px 0;border-bottom:1px solid #262a35;font-size:14px}}
</style>
<main>
<h1>ส่งไฟล์เสียงนักร้อง</h1>
<p>เลือกไฟล์เสียง (wav/mp3/m4a/ogg) แล้วกดส่ง ไฟล์จะเข้าคลังของ AR ทันที ไม่เกิน 60 MB</p>
{msg}
<form method="post" action="/upload" enctype="multipart/form-data">
  <input type="file" name="file" accept="audio/*" required>
  <button type="submit">ส่งไฟล์</button>
</form>
<p style="font-size:13px">คลังตอนนี้:</p>
<ul>{files}</ul>
</main></html>"""


def _render(msg: str = "") -> bytes:
    files = "".join(
        f"<li>{html.escape(p.name)} — {p.stat().st_size / 1024:.0f} KB</li>"
        for p in sorted(INBOX.iterdir()) if p.is_file()
    ) or "<li style='color:#6b7280'>ยังไม่มีไฟล์</li>"
    return PAGE.format(msg=msg, files=files).encode("utf-8")


def _parts(ctype: str, body: bytes):
    header = f"Content-Type: {ctype}\r\nMIME-Version: 1.0\r\n\r\n".encode()
    msg = email.message_from_bytes(header + body)
    for part in msg.walk():
        if part.get_content_maintype() == "multipart":
            continue
        name = part.get_filename()
        if name:
            yield name, part.get_payload(decode=True) or b""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._send(200, _render())

    def do_POST(self):
        if self.path != "/upload":
            self._send(404, _render())
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BYTES:
            self._send(413, _render("<p class='ok'>ไฟล์ใหญ่เกิน 60 MB</p>"))
            return
        body = self.rfile.read(length)
        saved = []
        for name, data in _parts(self.headers.get("Content-Type", ""), body):
            ext = Path(name).suffix.lower()
            if ext not in AUDIO_EXT:
                continue
            stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
            dest = INBOX / f"{stamp}-{Path(name).name}"
            dest.write_bytes(data)
            saved.append(dest.name)
            print(f"[+] saved {dest.name} ({len(data)} bytes)", flush=True)
        msg = ("<p class='ok'>รับไฟล์แล้ว: " + ", ".join(html.escape(s) for s in saved) + "</p>"
               if saved else "<p class='ok'>ไม่พบไฟล์เสียงที่รองรับ</p>")
        self._send(200, _render(msg))

    def log_message(self, *args):
        pass


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 12001
    print(f"voice inbox serving on :{port} -> {INBOX}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
