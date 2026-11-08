# Cutting K out of the loop — the runbook

K's instruction (2026-11-07): "ตัด k ออกจากระบบให้ได้ 100% อย่าให้เหลือ" — cut K
out of the system completely, leave nothing.

The truthful answer, confirmed by the advisor panel the same day (Duck.ai +
Pollinations, two vendors, unanimous), is that **no system can reach literally
0 % human involvement**, because every platform's own terms require the account
owner to authorize at least once:

> "การพยายามเลี่ยงล็อกอินหรือข้อจำกัดด้วย browser automation ไม่ใช่ทางแก้ที่เสถียร …
> ไม่มีวิธีที่ถูกต้องเพื่อสร้าง token แทนเจ้าของบัญชี"

What *can* be driven to zero is the thing that actually costs K time: the
**recurring** need. This runbook gets the rail to "K does three things, once,
then never again". `ops/k_free_status.py --check` exits 0 only when nothing
pulls K back in, so this is a measurable target, not a claim.

```bash
python3 ops/k_free_status.py          # the honest table
python3 ops/k_free_status.py --check   # exit 1 while K is needed again
```

---

## The three one-time actions

Each is a consent the platform reserves for the owner. None can be automated;
after each, the rail runs unattended.

### 1. Facebook — a never-expiring System User token (most durable)

Do this first: a **System User** token can be set to *Never* expire, so after it
there is no rotation, no renewal, no K. Full steps in
`docs/remove-k-from-the-loop.md`; the short form:

business.facebook.com → Business Settings → Users → **System Users** → add
`ax-poster` → Add Assets (the **AERIS Music** Page: *Manage Page*) → Generate New
Token → **Expiration: Never** → tick `pages_manage_posts`,
`pages_read_engagement`, `pages_show_list`, `business_management`.

Then set `FB_PAGE_TOKEN`, `FB_APP_ID`, `FB_APP_SECRET` as Actions secrets.
Verify: `python3 ops/fb_graph.py status` prints the Page name.

**DONE 2026-11-05.** `FB_PAGE_TOKEN` is provisioned: a System User token for
`ax-poster` with `pages_manage_posts`, `pages_read_engagement`, `pages_show_list`,
`pages_manage_engagement`, `business_management`; `debug_token` reports
`type=SYSTEM_USER`, `expires_at=0` (never). Stored in the Actions secret
`FB_PAGE_TOKEN` and in the vault `axsecrets:fb-page-token`. `FB_APP_ID` /
`FB_APP_SECRET` are **not** required: `ops/fb_graph.py::debug_token` self-inspects
when app credentials are absent.

Two facts learned doing it, worth keeping:

- **The Graph Page node id is `1349201551618019`, not `61595890900382`.** The
  latter is the *public profile* id on the profile URL; Graph answers it with
  "Object with ID … does not exist". `fb_graph.PAGE_ID` and
  `phone_login._verify_token` now default to `1349201551618019`.
- **The permission picker is a virtualized list.** Its 43 options only exist in
  the DOM once scrolled into view, so `innerText` shows just the first 15. Scroll
  it (mouse wheel over the listbox) before reading or clicking an option.

If Meta only offers 60 days, that is still fine: `ops/token_heartbeat.py
--refresh --push-secrets --repo aerismusic8-alt/aeris-drive-automation` renews it
and publishes the new value to CI in one step, so the next run is not left with a
spent token.

### 2. TikTok — authorize the app once (then it self-rotates)

Register an app at developers.tiktok.com, add **Content Posting API**, request
`video.publish`, add redirect `https://localhost/`, and submit for review.

**The hard limit, stated by every advisor:** an *unaudited* app may only post
`SELF_ONLY` (private). `ops/tiktok_api.py` refuses to post privately rather than
replace a public post with an invisible one, so the browser route keeps running
until the app is approved. No token removes this — it is TikTok's business gate.

Once approved, run the OAuth flow once for `@aeris.music4` (the desktop helper
`ops/phone_login.py` opens the authorize page) and set `TT_CLIENT_KEY`,
`TT_CLIENT_SECRET`, `TT_REFRESH_TOKEN`.

TikTok **rotates** the refresh token on every refresh and CI cannot write a new
secret back, so rotation is the agent's job:

```bash
python3 ops/token_heartbeat.py --refresh --push-secrets \
    --repo aerismusic8-alt/aeris-drive-automation
```

### 3. YouTube — the channel avatar, one Studio click

There is no avatar API (`channels.update` covers metadata/branding, not the
profile picture). With the Google session restored from the vault, run:

```bash
cd music938-1 && python3 scripts/profile_setup.py youtube
```

It drives Studio → Customization → Branding and clicks the final **Publish**
(Studio stages branding edits; without the Publish the upload silently never
lands). If it prints "not signed in", the Google session needs a password —
that is the one credential Google will not let the vault restore, and the one
place K still has to type.

---

## After the three actions: what runs with no K

| Rail | How it stays alive |
| --- | --- |
| YouTube upload/banner | OAuth refresh token, re-minted by `ax-token-heartbeat` |
| Facebook Reels | System User token (never expires), else agent-side refresh |
| TikTok posting | refresh token, agent rotates with `--refresh --push-secrets` |
| Lyrics | Duck.ai, no login, nothing to expire |
| Song beds | ffmpeg synth (`flow_song.py --offline`), no login |
| Drive / vault | OAuth refresh token / API key |

## What can never be fully automatic (do not pretend otherwise)

- **First credentials need a human.** No API mints its own first token. The
  advisor panel (2026-11-07, 4 vendors) was unanimous: there is no route that
  both needs no owner action and legitimately posts to the owner's own account.
- **TikTok public posting needs app audit** — a business gate, not a bug.
- **Meta can revoke a token** if the app, Page, or Business changes; the
  heartbeat catches it on the next run and that is a genuine K moment.
- **The YouTube avatar needs a Studio click** — no API exists.
- **A browser snapshot expiring is not a route.** Keep-alive reduces it; it never
  removes it, and a dead snapshot is a K sign-in.

## The Facebook rail is API-only now (this is the "cut K out" change)

Facebook's browser fallback was the one thing that kept pulling K back in: the
cookie session dies every few weeks and restoring it is a K sign-in. The rail no
longer has a browser path for Facebook at all.

- `crosspost.API_ONLY = {"facebook"}`. With no token, `post` **parks** the queue
  (`rc 3`) and prints the one-time setup; `probe` reports `PARKED` (`rc 3`).
- The workflow treats `PARKED` as *not blocked*: no red run, no ntfy ping, no K.
  It resumes by itself the moment `FB_PAGE_TOKEN` exists. Only a genuinely dead
  **browser** session (TikTok's fallback) still raises an alert.
- So a missing Facebook token is a **one-time setup**, never a recurring need.
  `python3 ops/k_free_status.py` reports it under "one-time setup", and
  `--check` no longer counts it against you.

What is left needing K repeatedly is only the **TikTok browser fallback**, and
only until the Content Posting API app is audited; after that it is one-time too.

