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

Packages are **not in the repo** and vanish on recycle:
`sudo apt-get install -y xvfb openbox x11vnc websockify novnc` plus
`python3 -m pip install playwright websocket-client`. `bootstrap.py` does this.

## The operator signs in — the agent never does

Give K this, with the VNC password from `.../aeris938-state/vnc.pass.txt`:

```
https://work-1-<work-host>/vnc.html?autoconnect=1&resize=scale
```

`<work-host>` is the **`work-1-...` host from the session's work_hosts block**, not
`hostname` (that returns the k8s pod name and answers 404).

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
