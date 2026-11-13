#!/usr/bin/env python3
"""A web live view of the cloud desktop browser, with control.

noVNC ships the whole 1600x900 X screen. This ships only the browser tab the
agent is working in, sized to the phone, with taps and typing forwarded as CDP
input. It is the free option (Rule #1): the browser is already running, and the
dependencies are `aiohttp` plus `websocket-client`.

    python3 ops/live_view_server.py --port 12001

Then open the session's work-2 host. Endpoints:

    GET  /              the page
    GET  /mjpeg         multipart JPEG stream (what the <img> shows)
    GET  /frame         one JPEG
    GET  /tabs          JSON list of open page targets
    GET  /health        JSON status
    POST /watch         {"id": "<targetId>"} to switch tab (omit id for newest)
    POST /input         {"t":"click","u":0.5,"v":0.3}  u,v are 0..1 of the frame
                        {"t":"scroll","u":..,"v":..,"dy":300}
                        {"t":"text","s":"..."} | {"t":"key","k":"Enter"}
                        {"t":"goto","url":"..."} | {"t":"reload"} | {"t":"front"}

Frames come from `Page.captureScreenshot` (~85 ms, ~12 fps measured), because
`Page.startScreencast` does not push frames on this sandbox's Chromium build.
MJPEG over plain HTTP is used instead of a WebSocket: an `<img>` renders it with
no client code, and it survives a stalled connection far better than a binary
WebSocket frame.
"""
from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

from aiohttp import web
import aiohttp

sys.path.insert(0, str(Path(__file__).resolve().parent))
from live_view import LiveView  # noqa: E402

VIEW = LiveView()
BOUNDARY = b"aereis-frame"

# The one-time Facebook token pages live in ops/phone_login.py. Only one port
# (12001) is reachable from outside, so phone_login runs on an internal port and
# those pages are proxied here rather than duplicated. The surface shortcuts
# below replace the rest of phone_login's job.
PHONE_PORT = 12002
PHONE_PATHS = ("/pass", "/fb-pass", "/fb-type", "/fb-grab", "/fb-token")

# The same shortcuts the phone page offers, so the live view is self-contained
# and does not need phone_login (which would want the same port).
SURFACES = [
    ("Flow Music", "https://www.flowmusic.app/"),
    ("Gemini", "https://gemini.google.com/app"),
    ("YouTube", "https://studio.youtube.com/"),
    ("TikTok", "https://www.tiktok.com/@aeris.music4"),
    ("Facebook", "https://www.facebook.com/61595890900382/"),
    ("Drive", "https://drive.google.com/drive/my-drive"),
    ("Shopee", "https://affiliate.shopee.co.th/dashboard"),
]

PAGE = """<!doctype html><html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>AERIS — Live View</title>
<style>
:root{--bg:#14121a;--panel:#221d2e;--line:#3a3150;--fg:#f2eef7;--dim:#a99fc4;--ok:#8ef0c0}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);
font:15px/1.5 system-ui,sans-serif;display:flex;flex-direction:column;height:100dvh}
header{display:flex;gap:8px;align-items:center;padding:8px 10px;background:var(--panel);
border-bottom:1px solid var(--line);flex-wrap:wrap}
select,button,input{font:inherit;color:var(--fg);background:#2c2440;border:1px solid var(--line);
border-radius:10px;padding:7px 10px}button{font-weight:700}
#bar{padding:3px 10px;color:var(--dim);font-size:12px;display:flex;gap:12px}
#surf{display:flex;gap:6px;overflow-x:auto;padding:6px 10px;background:var(--panel);
border-bottom:1px solid var(--line)}
#surf button{white-space:nowrap;font-size:13px;padding:6px 10px}
#stage{flex:1;overflow:hidden;display:flex;align-items:center;justify-content:center;background:#0b0a10}
#f{max-width:100%;max-height:100%;touch-action:none;display:block}
#type{background:var(--panel);border-top:1px solid var(--line);padding:8px 10px;display:flex;gap:8px}
#type input{flex:1}.dot{width:9px;height:9px;border-radius:50%;background:#ff6b6b}
.dot.on{background:var(--ok)}
</style></head><body>
<header><span class="dot on" id="dot"></span>
  <select id="tabs"></select>
  <button id="reload">โหลดใหม่</button>
  <button id="front">ยกขึ้นหน้า</button>
  <button id="shut">ปิดแท็บ</button></header>
<div id="surf"></div>
<div id="bar"><span id="stat">พร้อม</span><span id="res"></span>
  <a href="/pass" style="margin-left:auto;color:#9f93c0">🔑 รหัส Facebook (ครั้งเดียว)</a></div>
<div id="stage"><img id="f" alt="live"></div>
<div id="type"><input id="txt" placeholder="พิมพ์แล้วกด Enter…" autocapitalize="off">
  <button id="send">ส่ง</button></div>
<script>
const f=document.getElementById('f'), tabs=document.getElementById('tabs'),
      stat=document.getElementById('stat'), res=document.getElementById('res');
f.src='/mjpeg?_='+Date.now();
f.onload=()=>{res.textContent=f.naturalWidth+'x'+f.naturalHeight;};
f.onerror=()=>{stat.textContent='ภาพหลุด — กำลังลองใหม่';
  setTimeout(()=>{f.src='/mjpeg?_='+Date.now();},1000);};
function post(o){return fetch('/input',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify(o)});}
function uv(ev){const r=f.getBoundingClientRect();
  return {u:(ev.clientX-r.left)/r.width, v:(ev.clientY-r.top)/r.height};}
f.addEventListener('pointerdown',e=>{e.preventDefault();const p=uv(e);
  post({t:'click',u:p.u,v:p.v});});
f.addEventListener('wheel',e=>{e.preventDefault();const p=uv(e);
  post({t:'scroll',u:p.u,v:p.v,dy:e.deltaY});},{passive:false});
function loadTabs(){fetch('/tabs').then(r=>r.json()).then(d=>{tabs.innerHTML='';
  (d.tabs||[]).forEach(t=>{const o=document.createElement('option');o.value=t.id;
    o.textContent=(t.title||'').slice(0,26)+' — '+(t.url||'').slice(0,38);
    if(t.current)o.selected=true;tabs.appendChild(o);});
  tabs.onchange=()=>fetch('/watch',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({id:tabs.value})});});}
function loadSurfaces(){fetch('/surfaces').then(r=>r.json()).then(d=>{
  const box=document.getElementById('surf');box.innerHTML='';
  (d.surfaces||[]).forEach(s=>{const b=document.createElement('button');b.textContent=s.label;
    b.title=s.url;b.onclick=()=>fetch('/open',{method:'POST',
      headers:{'Content-Type':'application/json'},body:JSON.stringify({url:s.url})})
      .then(()=>setTimeout(loadTabs,1500));box.appendChild(b);});});}
document.getElementById('reload').onclick=()=>post({t:'reload'});
document.getElementById('front').onclick=()=>post({t:'front'});
document.getElementById('shut').onclick=()=>{if(!tabs.value)return;
  fetch('/close',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({id:tabs.value})}).then(()=>setTimeout(loadTabs,600));};
function send(){const i=document.getElementById('txt');if(i.value){post({t:'text',s:i.value});i.value='';}}
document.getElementById('send').onclick=send;
document.getElementById('txt').addEventListener('keydown',e=>{
  if(e.key==='Enter'){e.preventDefault();send();}});
loadTabs();loadSurfaces();
</script></body></html>"""


def apply_input(msg: dict) -> None:
    t = msg.get("t")
    if t == "click":
        VIEW.click_norm(float(msg["u"]), float(msg["v"]))
    elif t == "move":
        VIEW.move_norm(float(msg["u"]), float(msg["v"]))
    elif t == "scroll":
        VIEW.scroll_norm(float(msg["u"]), float(msg["v"]), float(msg.get("dy", 300)))
    elif t == "text":
        VIEW.text(msg.get("s", ""))
    elif t == "key":
        VIEW.key(msg.get("k", "Enter"))
    elif t == "goto":
        VIEW.goto(msg.get("url", ""))
    elif t == "reload":
        VIEW.reload()
    elif t == "front":
        VIEW.bring_to_front()


async def index(_req):
    return web.Response(text=PAGE, content_type="text/html", charset="utf-8")


async def frame(_req):
    data = await asyncio.to_thread(VIEW.capture, 60)
    if not data:
        return web.Response(status=503, text=VIEW._err or "no frame")
    return web.Response(body=data, content_type="image/jpeg",
                        headers={"Cache-Control": "no-store"})


async def mjpeg(req):
    resp = web.StreamResponse(headers={
        "Content-Type": "multipart/x-mixed-replace; boundary=" + BOUNDARY.decode(),
        "Cache-Control": "no-store",
    })
    await resp.prepare(req)
    try:
        while True:
            data = await asyncio.to_thread(VIEW.capture, 60)
            if not data:
                await asyncio.sleep(0.3)
                continue
            await resp.write(b"--" + BOUNDARY + b"\r\nContent-Type: image/jpeg\r\n"
                             b"Content-Length: " + str(len(data)).encode() + b"\r\n\r\n")
            await resp.write(data)
            await resp.write(b"\r\n")
            await asyncio.sleep(0.08)
    except (asyncio.CancelledError, ConnectionResetError, ConnectionError):
        pass
    return resp


async def tabs(_req):
    pages = await asyncio.to_thread(VIEW.pages)
    cur = (VIEW._target or {}).get("id")
    out = []
    for p in pages:
        url = p.get("url", "")
        # Test pages (data: URLs) and the blank tab are noise in a picker K uses.
        if url.startswith("data:") or url in ("", "about:blank"):
            continue
        out.append({"id": p.get("id"), "title": p.get("title", ""), "url": url,
                    "current": p.get("id") == cur})
    return web.json_response({"tabs": out})


async def close_tab(req):
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"ok": False, "err": "bad json"}, status=400)
    ok = await asyncio.to_thread(VIEW.close, body.get("id", ""))
    return web.json_response({"ok": ok, "err": VIEW._err})


async def health(_req):
    return web.json_response(VIEW.status())


async def watch(req):
    try:
        body = await req.json()
    except Exception:
        body = {}
    ok = await asyncio.to_thread(VIEW.watch, body.get("id"), False)
    return web.json_response({"ok": ok, "err": VIEW._err, "status": VIEW.status()})


async def input_post(req):
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"ok": False, "err": "bad json"}, status=400)
    try:
        await asyncio.to_thread(apply_input, body)
    except Exception as e:
        return web.json_response({"ok": False, "err": f"{type(e).__name__}: {e}"})
    return web.json_response({"ok": True})


async def surfaces(_req):
    return web.json_response({"surfaces": [{"label": l, "url": u} for l, u in SURFACES]})


async def phone_proxy(req):
    """Forward the one-time Facebook token pages to phone_login on PHONE_PORT.

    Those pages (password form, token form, grab-from-desktop) already exist and
    are tested; duplicating them here would be two places to keep correct. Only
    their URLs are visible, and the browser sees no difference.
    """
    body = await req.read() if req.method == "POST" else None
    url = f"http://127.0.0.1:{PHONE_PORT}{req.path_qs}"
    try:
        async with aiohttp.ClientSession() as s:
            async with s.request(req.method, url, data=body,
                                 headers={"Content-Type": req.headers.get("Content-Type", "")},
                                 allow_redirects=False) as r:
                data = await r.read()
                headers = {"Content-Type": r.headers.get("Content-Type", "text/html")}
                if r.status in (301, 302, 303, 307, 308) and "Location" in r.headers:
                    headers["Location"] = r.headers["Location"]
                return web.Response(status=r.status, body=data, headers=headers)
    except Exception as e:
        return web.Response(status=502, text=f"phone_login not reachable: {e}")


async def open_url(req):
    """Focus the tab for a surface if it is open, else open one, then watch it.

    Same behaviour as the phone page's /goto: reuse the existing tab so a signed-in
    surface is brought forward with its session instead of reloading.
    """
    try:
        body = await req.json()
    except Exception:
        return web.json_response({"ok": False, "err": "bad json"}, status=400)
    url = (body.get("url") or "").strip()
    if not url:
        return web.json_response({"ok": False, "err": "no url"}, status=400)
    tid = await asyncio.to_thread(VIEW.open_url, url)
    if tid:
        await asyncio.to_thread(VIEW.watch, tid, False)
    return web.json_response({"ok": bool(tid), "id": tid, "err": VIEW._err})


SERVE_DIR: Path | None = None


async def static(req):
    """Serve a file from --serve-dir, so this can stand in for the plain
    `python3 -m http.server` on 12001 (screenshots, and the bundle that
    push-via-pc1.sh fetches). `/` is the live view page, not a listing."""
    if SERVE_DIR is None:
        raise web.HTTPNotFound()
    rel = req.match_info.get("tail", "")
    target = (SERVE_DIR / rel).resolve()
    try:
        target.relative_to(SERVE_DIR.resolve())
    except ValueError:
        raise web.HTTPForbidden()
    if target.is_file():
        return web.FileResponse(target)
    raise web.HTTPNotFound()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=12001)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--serve-dir", default=None,
                    help="also serve files from this directory (e.g. /tmp/serve)")
    a = ap.parse_args()
    global SERVE_DIR
    if a.serve_dir:
        SERVE_DIR = Path(a.serve_dir)
    app = web.Application()
    app.router.add_get("/", index)
    app.router.add_get("/frame", frame)
    app.router.add_get("/mjpeg", mjpeg)
    app.router.add_get("/tabs", tabs)
    app.router.add_get("/health", health)
    app.router.add_post("/watch", watch)
    app.router.add_post("/input", input_post)
    app.router.add_post("/open", open_url)
    app.router.add_post("/close", close_tab)
    app.router.add_get("/surfaces", surfaces)
    app.router.add_route("*", "/pass", phone_proxy)
    app.router.add_route("*", "/fb-pass", phone_proxy)
    app.router.add_route("*", "/fb-type", phone_proxy)
    app.router.add_route("*", "/fb-grab", phone_proxy)
    app.router.add_route("*", "/fb-token", phone_proxy)
    app.router.add_get("/{tail:.*}", static)
    print(f"live view on http://{a.host}:{a.port}  (open via the work-2 host)")
    web.run_app(app, host=a.host, port=a.port, print=None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
