---
name: ax-cloud-desktop
description: Bring up and drive the persistent cloud desktop (Xvfb + openbox + x11vnc + noVNC + headful Chromium over CDP) so an agent can use login-only web apps such as Google Flow Music and Gemini web. Use when a task needs a signed-in browser, when a flowmusic.app or gemini.google.com action says "sign in", when a song or image must be generated from the web UI rather than an API, when noVNC returns 200 but nothing is on screen, or when a login was lost after a pod recycle.
triggers:
  - cloud desktop
  - novnc
  - vnc
  - flowmusic
  - flow music
  - gemini web
  - sign in
  - login lost
  - pod recycle
  - cdp
  - chrome profile
---

# The cloud desktop (persistent sign-in for web-only apps)

This exists for one reason: some tools have **no API** and are gated behind a Google
login the agent must never type. Flow Music and Gemini web are both like that. The
operator signs in once, in a browser the agent can drive, and the agent then works
through that same session.

Everything below was measured. Dates are UTC. When a step disagrees with what you
see, believe what you see and update this file.

## The three facts that decide everything

1. **`$HOME` is not persistent.** `/home/openhands` lives on the container overlay and
   is discarded when the pod recycles. **Only `/workspace` survives.** A chrome profile
   under `$HOME` therefore loses the Google login on every recycle, and the operator
   has to sign in again. That is the bug this skill fixes — the profile is kept under
   `/workspace/ax-tools/aeris938-state/`.
2. **A bare `--remote-debugging-port` is not enough to drive Chrome from Python.**
   Chrome rejects the CDP websocket with `403` and *"Rejected an incoming WebSocket
   connection from the origin ..."* unless `--remote-allow-origins='*'` is also passed.
   Without it every Playwright call fails and it looks like the browser is broken.
3. **`vnc.html` answers `200` even when the VNC backend is dead** — it is a static file.
   Never use the HTTP code as proof the desktop is up. Run `status`.
4. **The X screen does not repaint on this sandbox.** `scrot` of `:99` is
   byte-identical across seconds while the browser is active, so **noVNC shows a
   frozen picture** even though every process is up. This is why the desktop
   "looks dead". It is not the VNC transport — it is the renderer. Use the live
   view below, which does not ship the X screen at all.

## Bring it up

```bash
python3 /workspace/project/.agents/skills/ax-cloud-desktop/scripts/bootstrap.py
```

It installs what is missing, starts the five processes, and prints the operator's URL.
Idempotent: run it after every recycle. `--status` only reports.

The pieces, and what each one is for:

| Process | Why |
|---|---|
| `Xvfb :99` | the screen; there is no physical display |
| `openbox` | a window manager, so Chrome is not a single undecorated pane |
| `x11vnc :5900` | exports the screen |
| `websockify :12000` | bridges VNC to the browser so a phone can reach it |
| `chromium --remote-debugging-port=9222` | the browser the agent drives |
| `live_view_server.py :12001` | serves the **browser tab** as a live page with input |

## Live view — the view to use (2026-11-13)

`ops/live_view_server.py` serves the browser tab straight from CDP, not the X
screen. It is the answer to "noVNC is frozen": measured **~85 ms latency, ~12 fps,
~77 KB/frame** at quality 50, and it carries taps and typing.

```bash
python3 ops/live_view_server.py --port 12001 --serve-dir /tmp/serve
```

`bootstrap.py` starts it for you (step `start_liveview`). Endpoints: `/` (page),
`/mjpeg` (multipart JPEG the `<img>` shows), `/frame` (one JPEG), `/tabs`,
`/health`, `POST /watch`, `POST /input`.

Facts that cost time and will bite again:

- **`Page.startScreencast` is unusable here.** It yields exactly one frame and
  stalls — on the main browser *and* a second Chromium launched `--disable-gpu`.
  Use `Page.captureScreenshot` (`live_view.capture()`), which is live.
- **Never call `recv()` on one CDP websocket from two threads.** A background
  reader plus a request waiter deadlocked the server: `/frame` worked, the
  WebSocket never delivered. The transport is synchronous, one call at a time.
- **MJPEG over plain HTTP, not a binary WebSocket.** An `<img>` renders it with no
  client code and it survives a stall.
- `--serve-dir` keeps 12001's old job: `push-via-pc1.sh` fetches its bundle from
  there. Without it, that route breaks.

Packages are **not in the repo** and vanish on recycle:
`sudo apt-get install -y xvfb openbox x11vnc websockify novnc` plus
`python3 -m pip install playwright websocket-client`. `bootstrap.py` does this.

## The operator signs in — the agent never does

**Hand K the live view first:**

```
https://work-2-<work-host>/
```

`<work-host>` is the **`work-2-...` host from the session's work_hosts block**, not
`hostname`. `bootstrap.py` builds it from `RUNTIME_ID` and prints it; use that:

```
python3 .agents/skills/ax-cloud-desktop/scripts/bootstrap.py
```

noVNC (`https://work-1-<work-host>/vnc.html?autoconnect=1&resize=remote`, password
in `.../aeris938-state/vnc.pass.txt`) still works as a fallback, but on this sandbox
it shows a frozen picture — see fact 4 above. Reach for it only if the live view is
down.

### Signing in from a phone (the easy way)

`ops/phone_login.py` serves one page of large buttons on port 12001; open it from
the phone at `https://work-2-<work-host>/`. A tap opens that surface in the desktop
over CDP and then hands the phone to the **live view** already showing it, so the
only thing left to do is sign in (the password manager fills it). Health at
`/health`. The page never collects a password.

If the live view is down it falls back to noVNC. noVNC on a phone used to mean a
1600x900 desktop shrunk to fit, with an address bar a few pixels tall; `resize=remote`
(not `resize=scale`) fixes the sizing, which needs x11vnc `-xrandr` — `start()`
passes it. Do not switch it back to `scale`.

Google's **device-code** login is *not* a substitute: it mints an OAuth token,
not the browser cookie session Flow Music / TikTok / Shopee need.

### Self-heals to expect after a recycle

`start()` now repairs the three things that made the desktop read DOWN:

- `/tmp/.X11-unix` is wiped with the overlay, so Xvfb died with
  `_XSERVTransmkdir: ERROR: euid != 0` (needs root: `sudo mkdir -p
  /tmp/.X11-unix && sudo chmod 1777`).
- the profile on `/workspace` keeps a `SingletonLock` naming the **previous**
  pod, so Chrome refused to start ("in use on another computer").
- `ax-pylibs.pth` is lost, so every script dies with `ModuleNotFoundError:
  numpy` even though the wheels are still on `/workspace/ax-tools/pylibs`.

**Sessions die on their own, and a saved cookie set can be dead.** `restore()`
verifies each surface by loading it, because Facebook served the logged-out page
while still holding `c_user`/`xs` — a restore that only checks cookie presence
reports `ok` for a dead session. When it prints `SESSION REJECTED`, K must sign
in again through the noVNC URL, then run `ops/login_vault.py save`.

Then, **inside that screen**, K opens `flowmusic.app` (and `gemini.google.com`) and
signs in. Sign into both in one sitting — they share the same Google session.

**Which account: `aerismusic8@gmail.com`, K's account.** K ruled on 2026-10-31 that
Flow Music and Gemini run on K's own account and **not on a mailbox AR registered**
(AR's mail.tm address `araeris2909e0@fldubai.com`). A fresh signup in either app
means the wrong account is in the profile. `check_login.py` now prints the account
and returns `RESULT=WRONG_ACCOUNT` (exit 3) when it is not the expected one — treat
that as a stop, sign out, and sign back in as `aerismusic8@gmail.com`.

**The free allowance, measured 2026-10-31** (`GET /__api/billing/credits`, free
tier): `tokens_remaining` 4510, `credits_remaining` 376, plus a `daily-free` grant
of **360 tokens / 30 credits each day**. `producer/access-granted: true`. A song
(create + extend) draws a few hundred tokens, so one account sustains only a
couple of songs a day — the throttle window, not the balance, is usually the
binding limit. K's standing permission if a free allowance cannot finish the job:
create more accounts (Flow/Gemini stay on K's account).

**Do not send K a session URL and expect it to help.** A link like
`flowmusic.app/session/<uuid>` is an in-app route, not a credential. Opened without a
login it redirects to the landing page and shows *Log in / Sign up*. The cookie has to
live in *this* browser; a login done on K's own phone is on K's own phone.

## Prove the login is real before working

```bash
python3 scripts/check_login.py            # prints cookie counts and the account
```

A working login shows ~27 cookies for `.google.com` **and** `myaccount.google.com`
resolving to the account email. Two cookies (`theme`, a posthog id) mean **not signed
in**, whatever the page title says.

`flowmusic.app` also needs its **own** session: signed in to Google, the site still
shows a `Create a song` button with **0 input boxes**. Click it; the composer appears as
`textarea[placeholder="Ask Producer..."]` and there are 4 textareas. A missing composer
is the login signal — detect the landing copy instead of waiting for a locator to time out.

## Drive it

Playwright attaches to the running browser; it does not launch its own:

```python
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    b = p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    pg = b.contexts[0].pages[0]
```

Screenshots are how you see what K sees:

```bash
python3 scripts/shot.py /tmp/desk.png     # CDP Page.captureScreenshot
```

## Generating a song (Flow Music)

1. `Create a song` -> composer -> type the prompt -> `button[aria-label='Send message']`.
2. It narrates a title and renders for roughly 2-4 minutes. **Wait for the duration
   readout to move off `0:00`**; the progress percentage disappearing is not the finish.
3. Download is behind `More options for <title>` -> `Download` -> **a submenu**
   (`Download video`, `Get stems`, `M4A`, `MP3`, `WAV`). The `MP3` node is a `div`, not a
   button, and a plain `.click()` times out. Use
   `Browser.setDownloadBehavior` with an explicit `downloadPath` and click the leaf
   through JS. See `scripts/flowmusic_download.py`.
4. Register the file in the library so `make_story.py` reuses it:

```bash
python3 -c "import sys; sys.path.insert(0,'scripts'); import library; \
library.add('music','01-hin-haeng-khwam-jam-mood',__import__('pathlib').Path('<file>.mp3'),\
source='flowmusic-web', provider='www.flowmusic.app', mood='...')"
```

`make_story.py` prefers a library track over the synth bed and looks it up by
`f"{name}-mood"`. `compose.py` loops a short track with `-stream_loop -1`, so a 3-minute
song fills a 5-minute episode.

## After a recycle

```bash
python3 .../ax-cloud-desktop/scripts/bootstrap.py     # restarts everything
python3 .../ax-cloud-desktop/scripts/check_login.py   # expect: signed in
```

If `check_login.py` says signed out, the profile was not where this skill keeps it, or
the profile directory was wiped. Re-do the operator sign-in once. It should be rare —
that is the whole point of `/workspace`.
