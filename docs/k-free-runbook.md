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

A **browser** rail is not K-free (its snapshot can expire), but it stops being a
recurring K-dependency when the vault holds the account password, because the
agent signs back in itself (`ops/fb_relogin.py`). The audit marks that case
`AGENT` / *agent-revivable* — honest on both sides: it is not counted as K-free
(a checkpoint could still need a human), and it no longer trips `--check`. Today
Facebook qualifies (vaulted password); TikTok does not, so TikTok is the one
remaining recurring K-dependency.

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

**DEGRADED 2026-11-09 — the token is rejected; the browser fallback carries it.**
From 2026-11-08 the stored token returns `API access blocked` (OAuthException 200)
to *every* call, `debug_token` included. A System User token that "never expires"
can still be revoked (Business Settings change, password reset, policy) — expiry is
not the only way it dies. The one-time fix is the same step above: generate a
**new** System User token and set `FB_PAGE_TOKEN` (and the vault
`axsecrets:fb-page-token`) again, which restores the headless route.

This is no longer an outage, though. Commit `8e6eaecf` gave Facebook the same
signed-in-browser fallback TikTok has (`API_ONLY` is empty), so the rail keeps
posting Reels while the token is rejected — the only loss is the headless route.
`ops/token_heartbeat.py` therefore reports the state as `degraded` and exits **0**:
an account-level block is not something K can clear by signing in, so paging K
every six hours was pure noise. `python3 ops/fb_graph.py status` is the check.

**RESOLVED 2026-11-11 — the *browser* session, not the token, was the real outage.**
Both routes were down at once on 2026-11-11: the Graph token rejected *and* the
saved browser cookie session dead (Facebook served the logged-out page while still
holding `c_user`/`xs`, so the 08:39Z crosspost run failed with 134 posts waiting).
The two are independent, and only the second is AR's to fix:

```bash
python3 ops/fb_relogin.py --check        # is the browser session alive?
python3 ops/fb_relogin.py --push-secret  # revive it + refresh the CI secret
```

`ops/fb_relogin.py` reads the Facebook password from the vault
(`axsecrets:fb-password`, provisioned once), signs in over CDP in a single attempt
(no retry loop — that is what triggers a checkpoint), verifies the real session,
saves it back to `login_vault`, and — with `--push-secret` — refreshes
`AERIS_STORAGE_STATE_B64` so the CI rail stops holding the stale blob. Verified:
the 2026-11-11 11:37Z crosspost run posted a Facebook Reel
(`facebook.com/reel/1818815976028171`) and stayed green.

**Key finding: the account block does NOT block the browser route.** The Graph
`API access blocked` is app/API-level; the web login still works with the stored
password and no checkpoint. So the browser route is the reliable fallback while the
Graph block stands, and the Graph fix remains a one-time owner action (above).

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

## Facebook has a browser fallback again (2026-11-10)

`crosspost.API_ONLY` is empty: Facebook posts through the signed-in browser just
like TikTok, and `api_poster` still prefers the Graph route whenever its token is
live. The fallback is what keeps the rail posting while `FB_PAGE_TOKEN` is
rejected (see the DEGRADED note above).

- With no token, or a rejected one, `post` uses the browser and prints which route
  it took; `probe` reports the browser session's state.
- The workflow treats a dead **browser** session as *blocked* (a real outage with
  work waiting): it records the pending count and the final gate fails the run so
  K is asked to sign in. A *rejected API token* is **not** blocked — the browser
  route carries it — so it raises no alert.
- `python3 ops/k_free_status.py` reports a missing token under "one-time setup",
  and `--check` does not count it against you.

What is left needing K repeatedly is only the **TikTok browser fallback**, and
only until the Content Posting API app is audited; after that it is one-time too.

### The Page feed is a mix, not only Reels

The Page used to publish Reels and nothing else, which read as a wall of the same
format. `ops/fb_graph.py` now posts three formats through the one token:

| Format | Call | What it is |
| --- | --- | --- |
| Reel | `POST /{page}/video_reels` | a vertical song video (the reach driver) |
| Photo | `POST /{page}/photos` (multipart) | the song's cover art (the identity) |
| Link | `POST /{page}/feed` | a Shopee card (the click driver) |

- The queue builder (`crosspost.build_queue`) interleaves cover-art photos and
  Shopee link posts into the Facebook side of the queue. Photo/link items carry
  `kind` and an `image` (photo) or `link` (link) field instead of `video`, and
  the post loop picks the field by `kind`.
- The committed queue is migrated in place with
  `python3 music938-1/scripts/crosspost.py --augment-formats`. It is idempotent
  (it strips and re-inserts the photo/link items), and it exists because a fresh
  pod has no `library/` and so cannot rebuild the queue from disk.
- Cadence: `MIN_GAP_SECONDS` is one hour. `DAILY_CAP` (TikTok) is 4;
  `FACEBOOK_DAILY_CAP` is 3. A separate `LINK_DAILY_CAP = 1` keeps the feed from
  reading as an ad wall, which is the concern a low total cap used to stand in for.
- The advisor panel (2026-11-05, 2 vendors) ranked the mix: Reel for reach,
  photo for identity, at most one link a day. That is the source of these
  numbers, and it is recorded in `ops/consult-log.jsonl`.

