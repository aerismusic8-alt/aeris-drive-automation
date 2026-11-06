# Brief: followers are not moving on any of the three surfaces

You are advising a tiny Thai music channel run by AI, aiming at revenue. We need
a concrete diagnosis and a plan, not encouragement.

## The real numbers (measured 2026-11-05, from the platforms' own APIs/dashboards)

YouTube @aerismusicth (channel ch3), 11 days old:
- 7 subscribers, 2,034 total views, 22 videos.
- Views per upload are FALLING: the 2026-11-01 Shorts got 152-232 views, the
  2026-11-05 Shorts got 11-22 views.
- 0 comments on almost every video (1 total). Likes 0-5.

Facebook Page "AERIS Music": **1 follower**, views UNKNOWN (not readable).
TikTok @aeris.music4: **0 followers**, views UNKNOWN.
Shopee affiliate: clicks/orders UNKNOWN (dashboard behind an anti-bot wall).

## What we publish (this is the part we can change)

- 9 songs exist; only **5 have Shorts**. The 25 Shorts are cut from those 5 songs
  (song 01 has 9 Shorts, song 02 has 6).
- Each Short is a vertical 9:16 lyric/karaoke cut of one chorus, bedded on the AI
  song. Titles like "คนดีที่จากไป (ท่อนที่ 1) #เพลงไทย #Shorts" (part 1 of 3 of the
  same song).
- We upload 6 Shorts/day to YouTube (the Data API quota ceiling is 10,000
  units/day; each upload costs 1,600).
- TikTok and Facebook get the SAME vertical clips with a Thai caption + the
  Shopee affiliate link. Both surfaces have been effectively **paused for weeks**
  because the saved browser sessions died and the posting step was silently
  skipped.
- Thai-language lyrics are AI-generated; the vocal is AI; the cover art is
  AI-generated.

## Constraints (do not propose anything that violates these)

- FREE tools only. No paid ads, no paid promotion, no paid scheduling services.
- No bots that fake engagement (no view/like/follower buying) — it breaches the
  platforms' terms and would kill the accounts.
- We can drive a signed-in browser, the YouTube Data API (OAuth), and plain
  HTTP. We do NOT have: paid tools, a team, or a human who can appear on camera.
- Thai audience is the target.

## Questions

1. Diagnose the stall. Given 7/1/0 followers and falling Short views, what is the
   single most likely cause? Rank: (a) content quality, (b) wrong audience/topic,
   (c) upload cadence/algorithm, (d) too few distinct songs so Shorts look
   repetitive, (e) cross-surface posting broken, (f) something else.
2. Is "6 Shorts/day cut from only 5 songs" actively harmful (duplicate-content
   suppression) versus helpful (more shots on goal)? What cadence would you run
   with 9 songs and free tools only?
3. What is the fastest honest lever to get the FIRST 100 followers on a
   brand-new Thai music Shorts channel with zero budget? Be specific and
   executable by a script (e.g. exact title/hashtag format, posting times,
   reply strategy, cross-posting order, a "series" format).
4. Should the channel change format entirely (e.g. lyric videos with a
   sing-along hook, a named recurring series, Thai trending-audio angle), or
   double down on the current karaoke Shorts?
5. Give a 7-day, free, script-executable plan with a measurable target and the
   one metric to watch.
