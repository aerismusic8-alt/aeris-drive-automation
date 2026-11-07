# Brief: make the AERIS automation 100% free of K (no human in the loop)

## The demand
K's charter says run 24/7 and "NEVER ask K". But the system still stops and asks
K in several places. K now wants it stated plainly: **take K out of the loop
100%.** Not "mostly", not "for posting" — the whole automation.

## What the system is
A one-person Thai AI music label run by an agent (AR) in a disposable Linux
sandbox, plus GitHub Actions on a public repo (free minutes). Surfaces: YouTube
`@aerismusicth` (ch3) + 3 more channels, Facebook Page "AERIS Music", TikTok
`@aeris.music4`, Shopee affiliate, and a Roblox game. Revenue: Shopee affiliate
+ AdSense later. Rule #1: free tools only.

## Where K is still required — the honest audit (2026-11-07)

Every one of these is a place the automation stops and a human has to act. They
fall into two kinds, and the distinction is the crux of the question:

**A. Recurring (K must act again and again) — these are the real defects**
1. **Facebook posting.** The Page is posted through a *browser session* (Playwright
   over CDP on a cloud desktop). It has died: the last run said
   `facebook session is dead`, 64 Reels are stuck pending, and the job fails red,
   which pages K on ntfy. The fix that removes K is a Meta **System User token**
   (`pages_manage_posts`), which never expires and posts over the Graph API with
   no browser. The code path exists (`ops/fb_graph.py`) but the token does not.
   A token must be minted in Business Manager, which needs a logged-in human.
2. **TikTok posting** still rides a browser session restored from a K-created
   secret (`AERIS_STORAGE_STATE_B64`). It works today but will expire, and then
   it is another K sign-in. The TikTok **Content Posting API** (refresh token)
   removes the browser entirely.
3. **Content generation.** Lyrics come from driving **gemini.google.com** in a
   browser, and music from **flowmusic.app** — both login-only Google web apps.
   That is a browser session per pod, i.e. a K login whenever the session is lost.
4. **The avatar** (done once) and any Studio-only change: no API exists.
5. **The OpenHands vault** (`login_vault`, `ax_vault`) needs `OPENHANDS_API_KEY`.
   When it is absent the KV calls return 401 and scripts die, which also asks K.

**B. One-time (K acts once, then never again) — acceptable, if truly once**
- Minting the FB System User token, and the one TikTok/Google authorisation.

## The question
1. **Can the recurring set be driven to zero?** Specifically: is a Meta System
   User token genuinely non-expiring, and is it the right call, or should we use
   a 60-day user token refreshed by a scheduled job (and what breaks in 60 days
   if that job is the only thing holding it up)?
2. **How do we remove the browser from content generation?** Free-tier API
   alternatives for Thai lyrics (Gemini API / Groq / OpenRouter free tier?) and
   for music beds. If a free API cannot match, is the honest answer "keep the
   browser, but make the session durable" — and how durable can that be?
3. **What is the irreducible core?** Which parts of this genuinely cannot be
   automated without holding a credential we are forbidden to hold (passwords,
   MFA), and how do we make those happen *once* and survive pod death, sandbox
   replacement and 60-day expiries?
4. **How should the system behave when a K-only step is pending?** Today a dead
   session turns the job red and pages K. Is there a better contract — e.g. a
   single "K-free: NO, blocked on X" status surface that is not an alarm, so a
   known-pending one-time step stops reading as a failure?
5. **Is there a route we have missed** — e.g. does Meta still allow generating a
   long-lived Page token from a User token via `/me/accounts`, and can TikTok's
   Content Posting API be authorised once and refreshed forever?

## What we want back
A concrete target architecture: which rail uses which credential, which
credential expires and when, what refreshes it, and the shortest list of
one-time human steps that remains. Be explicit about what you would refuse to
automate and why. Assume free tools only, and assume the operator will not hand
over a password.
