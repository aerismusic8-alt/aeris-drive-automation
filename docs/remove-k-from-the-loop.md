# Cutting K out of the loop — the one-time token setup

The rail posts to four surfaces. YouTube already runs headless on a refresh token.
Facebook and TikTok used to post by driving a browser with a saved cookie session,
and that session dies every few weeks — which is why K had to sign in again.

The fix is to post through each platform's **API** instead, with a token that
outlives a cookie. The code is already in place (`ops/fb_graph.py`,
`ops/tiktok_api.py`, wired into `music938-1/scripts/crosspost.py`); it stays inert
until a token exists, so nothing breaks today. This file is the single interactive
step: provision the tokens once, and K never signs in for this again.

Advisor panel 2026-11-07 (6 channels / 4 vendors) ranked the routes:

| Rank | Route | Durability |
| --- | --- | --- |
| 1 | Meta Graph API + **System User** token | best — can be non-expiring |
| 2 | TikTok Content Posting API + OAuth | better than cookies, but has a hard limit |
| 3 | browser session keep-alive | worst — do not invest here |

---

## Facebook (do this first — it is the durable one)

1. Go to **business.facebook.com → Business Settings → Users → System Users**.
2. **Add** a system user (name it `ax-poster`, role *Employee* or *Admin*).
3. **Add Assets** → Pages → select **AERIS Music** → give it *Manage Page* (or
   *Content* → *Create content*).
4. **Add Assets** → Apps → select the Meta app you will use, or create one at
   developers.facebook.com (**Business** type). Give the system user access.
5. Click **Generate New Token**, pick the app, and tick:
   `pages_manage_posts`, `pages_read_engagement`, `pages_show_list`,
   `business_management`, plus `publish_video` if it is offered.
6. Set **Token expiration** to **Never** if the option is there. If Meta only
   offers **60 days**, that is fine — `ops/token_heartbeat.py --refresh` renews it
   with the app secret and never needs K again.
7. Copy the token. Also note the **App ID** and **App Secret** from the app's
   Settings → Basic.

Then set four GitHub Actions secrets (repo → Settings → Secrets and variables →
Actions). Use the helper so nothing is typed twice:

```bash
./scripts/use-app-token.sh            # writes the workflow token to the remote
python3 scripts/gh-api.py PUT /repos/aerismusic8-alt/aeris-drive-automation/actions/secrets/FB_PAGE_TOKEN --body-file <(printf '{"encrypted_value":"...","key_id":"..."}')
```

`gh secret set` is simpler if the `gh` CLI is available with a writable token:

```bash
gh secret set FB_PAGE_TOKEN   --body "<token>"
gh secret set FB_APP_ID       --body "<app id>"
gh secret set FB_APP_SECRET   --body "<app secret>"
```

Verify: `python3 ops/fb_graph.py status` should print `configured` and the Page
name **AERIS Music**.

## TikTok (do this second — read the limit first)

**The hard limit, stated plainly by all four vendors:** TikTok's Direct Post API
requires the app to pass TikTok's audit before it can publish publicly. An
*unaudited* app may only post `SELF_ONLY` (private, visible to the creator only).
`ops/tiktok_api.py` detects this and **refuses to post** rather than silently
replacing a public post with an invisible one — so until the app is audited the
browser route keeps running. That is a business gate, not a bug, and no token
removes it.

1. Register an app at **developers.tiktok.com** → *Manage apps* → *Connect an app*.
2. Add the **Content Posting API** product. Request the **`video.publish`** scope.
3. Add the redirect URI `https://localhost/` (unused, but required).
4. Submit the app for review. Until it is approved, posts are `SELF_ONLY`.
5. Once approved, run the OAuth flow once to get a refresh token (the desktop
   helper `ops/phone_login.py` opens the authorise page for `@aeris.music4`).

Set the secrets:

```bash
gh secret set TT_CLIENT_KEY     --body "<client key>"
gh secret set TT_CLIENT_SECRET  --body "<client secret>"
gh secret set TT_REFRESH_TOKEN  --body "<refresh token>"
```

Note: TikTok **rotates** the refresh token on every refresh, and a GitHub Actions
job cannot write a new secret back. So CI only *checks* (`ops/token_heartbeat.py`),
and the agent rotates with `python3 ops/token_heartbeat.py --refresh`, which writes
the new token to the vault. This is why the heartbeat workflow never passes
`--refresh`.

---

## What is automatic after this

- `ax-music-crosspost` posts via the API with **no browser and no cookie** — the
  probe reports the API surfaces as signed in without launching Chromium.
- `ax-token-heartbeat` runs every 6 hours and pages K on ntfy **only** when a
  token has actually lapsed.
- The browser route stays as a fallback: delete the secrets and it returns to
  exactly the old behaviour.

## What can never be fully automatic (be honest about this)

- **TikTok public posting needs app audit.** Until then it is private-only via API.
- **Creating a token needs a human once.** No API mints its own first credential.
- **Meta can revoke a token** if the app, the Page, or the Business changes — the
  heartbeat catches it the next run.
