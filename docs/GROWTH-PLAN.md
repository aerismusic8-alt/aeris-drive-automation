# Growth plan — how AR grows the followers (verified 2026-11-13)

K's order (2026-11-13): "มีทีม มีมือมากมาย ... ให้ทีมไปล่าหาผู้ติดตาม กระจายงานออกไป
ตามกลุ่มต่าง ๆ สมัครเครื่องมือทำคอนเทน ปัง ๆ กระจาย สร้างโปรไฟล์ เอาให้เต็ม
ความสามารถเลย." This file records what was actually checked, what the free
constraints allow, and the ranked plan. Numbers here were read from the running
system, not estimated.

## What the team already has (audited, not assumed)

| Piece | State | Evidence |
|---|---|---|
| 7 sub-agents | present | `.agents/agents/{ax-advisor,ax-delivery,ax-evidence,ax-experiment,ax-hygiene,ax-session}.md` |
| OpenHands automations | 12 defined, **all disabled** | `GET /api/automation/v1` |
| 6 publishing rails | **live** (release, compilation, crosspost, admin, session-heal, dashboard) | `GET /actions/workflows` |
| 5 render rails | off on purpose | backlog drain |
| Landing page | **live, HTTP 200**, SEO JSON-LD + affiliate | `aerismusic8-alt.github.io/site-aeris-music` |
| Cross-post surfaces | Facebook Reels + TikTok | `.github/workflows/ax-music-crosspost.yml` |
| Follow ask in copy | present on YT desc, FB, TikTok | `release.py`, `crosspost.caption()` |

## The hard constraint: outbound follow automation is banned

`aeris938-2/scripts/outreach.py --follow` and `--invite` **refuse to run** without
`--i-understand-the-risk`. Reason on file (2026-11-06): a panel of five advisors
answered unanimously — reciprocal following and bulk friend-invites are an
artificial-growth signal, and Meta's spam policy keys on the *pattern*, not on a
safe per-day number, so slower pacing does not make it safe. K cannot risk the
account.

Consequence: `AX Music Growth (follow suggested pages)` stays **off**. Its
auto-pause ("last 5 runs all failed") was in fact the hold guard firing — the
plugin calls `--follow` with no risk flag and gets exit 3. It is not a bug to fix
by adding the flag; that would re-arm exactly what the panel banned.

## What was actually broken and is now fixed

1. **Facebook posted nothing for hours** while 100+ Reels waited. A `photo` at
   the head of the queue ate the single `--limit 1` slot and was then skipped as
   un-postable (Graph API blocked). Fixed; verified live with a real Reel.
2. **Search was 0% of views.** The lyric was written to disk for every song and
   never read by `describe()`, so no upload carried its own lyric. Fixed for new
   uploads and backfilled onto the live catalogue.
3. **The measurement rail was auto-paused.** `market.py` raised a raw 403 when
   the shared quota pool was spent; five such days read as five crashes. Now rc 3
   ("spent for today"), so the rail survives an empty pool.

## Ranked plan (safe, free, highest leverage first)

### 1. Cross-promote inside the account's own four channels
ch1 `@tatagenxgeny` (philosophy), ch2 `@farmmer-n9t` (dhamma), ch4
`@kongkeatpratumma` (drama) already have a viewer base that ch3 does not reach.
A pinned comment, a description line and an end card on each pointing to ch3
costs nothing, carries no spam signal (it is the owner's own content), and
reaches a Thai audience that already chose to follow a Thai channel.
**Action:** add a `ช่องเพลงของเรา` line to each channel's description block and a
pinned pointer on the newest upload of each.

### 2. Keep the short-form cadence, keep the follow ask
Shorts are the free discovery surface and the follow ask is already in every
caption. The pilot cadence (6 h gap, 4/day) is the anti-flood setting; hold it
and let the lyric fix compound. Volume is the known lever — long-form
compilations carry ~1 h of watch-time per view toward the 4,000-hour gate.

### 3. Refresh the free landing page on every release
The page is live and already carries the SEO JSON-LD and the affiliate link, but
it only refreshes when `market-daily` runs. With the quota fix it now runs
daily again. Confirm the page picks up each new song, and add the lyric text to
the page body — the same search surface fix, applied to the one site AR owns.

### 4. Use the cloud desktop for the login-only surfaces
The signed-in Chromium is the free route to any surface with no API. Instagram
Reels would widen reach using the same browser session as Facebook; it is the
next cross-post surface to evaluate, and it needs no new credential if the
desktop session already covers it.

## Blocked, and whose action unblocks it

| Block | Owner action | Free route that still works |
|---|---|---|
| FB Graph token: `API access blocked` (OAuthException 200) | K unblocks the app in the developer console | browser session posts Reels (verified) |
| `yt_comment.py`: needs `youtube.force-ssl` | K re-mints the refresh token with that scope | the offer reaches viewers via the description |
| YouTube upload cap (account-level, shared 4 channels) | clears on a rolling ~24 h window | the release cron picks up automatically |
| Instagram / other login-only apps | K signs in once on the cloud desktop | the agent never types a password |

## Rule reminder

Everything above is free. No paid tool, subscription, credit pack or API is
proposed anywhere in this plan (Rule #1).
