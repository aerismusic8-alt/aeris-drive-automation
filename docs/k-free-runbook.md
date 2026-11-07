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

- **First credentials need a human.** No API mints its own first token.
- **TikTok public posting needs app audit** — a business gate, not a bug.
- **Meta can revoke a token** if the app, Page, or Business changes; the
  heartbeat catches it on the next run and that is a genuine K moment.
- **The YouTube avatar needs a Studio click** — no API exists.
- **A browser snapshot expiring is not a route.** Keep-alive reduces it; it never
  removes it, and a dead snapshot is a K sign-in, which is why every fallback
  here has a K-free primary in front of it.
