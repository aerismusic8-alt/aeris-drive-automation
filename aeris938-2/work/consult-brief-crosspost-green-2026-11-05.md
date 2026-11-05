# Brief: the crosspost rail reports success while posting nothing

## The situation (real numbers, not guesses)

AERIS Music runs four surfaces on GitHub Actions (free, always-on). One rail,
`AX Music Crosspost` (`ax-music-crosspost.yml`, cron `0 */2 * * *`), posts
pending Shorts to the Facebook Page (`61595890900382`) and TikTok
(`@aeris.music4`).

Observed today (2026-11-05):

- The rail's last three runs (01:56Z, 08:58Z, 15:53Z) all ended
  `conclusion: success`.
- In every run the probe step wrote `FB_STATE: SIGNED_OUT` and
  `TK_STATE: SIGNED_OUT`, and the post step printed
  `--- facebook: skipped (session not signed in) ---` and the same for tiktok.
- So the run posts **nothing**, yet is green. K gets no alert, because the ntfy
  step only fires `if: failure()`.
- The saved session is `AERIS_STORAGE_STATE_B64` (Playwright storage state,
  cookies + localStorage, exported with `ops/save_storage_state.py` from the
  cloud desktop's Chromium). A `login_vault.py save` snapshot was taken today
  07:28Z (247 cookies: 11 facebook, 26 tiktok).
- The cloud desktop's Chromium is itself signed out of **everything** now:
  YouTube Studio redirects to `accounts.google.com/.../accountchooser` showing
  "Signed out" for both accounts; Facebook and TikTok upload pages redirect to
  login. The vault restore (cookies + localStorage) does not revive it — the
  servers reject the restored session.
- The last successful Facebook Page post was 2026-11-05T10:08Z and the last
  successful TikTok post 2026-11-05T08:59Z, so the session died mid-morning.

## Constraint

Rule #1: free tools only. No paid session-persistence or anti-bot service. The
Google/Facebook/TikTok passwords are never typed by the agent — a human signs in
once via the cloud desktop (noVNC). A brand-new sandbox loses `/workspace` state,
so the vault is the only durable store.

## The question

1. Is "green rail, zero posts" the right thing to fix first, or is chasing the
   dead login the wrong lever when the real problem is that 2,022 lifetime views
   produce 0 Shopee clicks?
2. What is the highest-value thing AR can do **without** a signed-in session
   (the only surface that still answers is the YouTube Data API and Duck.ai,
   which needs no login)?
3. Should the rail be changed to fail (red + ntfy) when the session is dead and
   nothing posts, so the failure is visible? Any downside to making a "nothing
   to do" run distinguishable from a "blocked" run?
4. Is there any free, non-bannable way to keep a Facebook/TikTok web session
   alive longer (heartbeat cadence, storage-state refresh), or is a periodic
   human sign-in simply the cost of a login-only surface?
5. Given ~2,000 views and 0 conversions, what one change would most likely
   produce the first real Shopee click or the first baht of revenue?
