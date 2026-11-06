# Brief: an AI agent that runs the Facebook Page like a human admin, 24/7

## What K asked (2026-11-06, verbatim intent)

K wants an AI agent to act as the Page's admin: "ตามหาผู้ติดตาม" (go find
followers), "ตอบโพสต์" (reply to posts/comments), "ดันคลิป" (push/boost the
clips), "ทำทุกอย่างให้เพจโต" (do everything to grow the Page), "ทำงาน 24*7".

## Our real situation (all verified, do not re-argue)

- **Page "AERIS Music"** (id 61595890900382). Read *as the Page*: **861 views /
  28 days, 99.9% from non-followers**, top Reel 129 views, Page status
  "แนะนำได้" (eligible, not restricted). So distribution works; the Page is tiny
  (1 follower), not suppressed.
- **Content rail already exists and runs on a schedule.** GitHub Actions
  (`ax-music-crosspost.yml`) posts clips to Facebook + TikTok through a headless
  Chromium that loads a saved session from a base64 secret
  (`AERIS_STORAGE_STATE_B64`). A separate `ax-music-release.yml` uploads to
  YouTube via OAuth refresh tokens. Cadence is capped: FB 2 clips/day, min gap
  20 min.
- **A growth loop already exists**: `aeris938-2/scripts/outreach.py` follows
  niche Pages as the Page and invites the personal profile's friends to like the
  Page, deliberately slow (per-run limit, min gap, daily cap), state in
  `work/outreach-state.json`.
- **The always-on runner is GitHub Actions**, not the cloud desktop. The desktop
  (Xvfb + Chromium over CDP) dies when the pod recycles; only Actions keeps
  running unattended. FB/TikTok/Shopee have no usable API, so those actions need
  a browser — in CI that is a headless Chromium with the saved session.
- **Rule #1: free only.** No paid API, no ads, no paid promotion, ever.
- One human (K) is the only person who can sign in, and the only real social
  network (friends/groups) belongs to K's personal profile.

## The question

We want to build an agent that does the Page-admin job unattended, on a
schedule, for as long as possible, and we must not get the Page or the account
banned. Please answer concretely:

1. **Which of these can be automated safely at all, and which must stay manual?**
   (a) posting clips on a schedule; (b) following niche Pages to earn follows;
   (c) inviting K's friends to like the Page; (d) replying to comments on our
   own Page; (e) commenting on / engaging with *other* Pages' posts;
   (f) messaging; (g) joining and posting in groups; (h) replying to DMs.
   For each: safe / risky / ban-bait, and why.
2. **What are the concrete ban triggers** Meta enforces against Page automation
   in 2025-2026 (follow/unfollow velocity, identical comments, link spam,
   engagement pods, new-Page volume limits), and what is the maximum safe rate
   per day for a Page that is ~1 week old with 1 follower?
3. **Should the agent act from the Page identity or the personal profile?**
   Which actions belong to which identity, and what is the risk of each?
4. **What is the highest-value, lowest-risk automation for the next 30 days** for
   a Page with good distribution but no audience? Rank the actions.
5. **Is "reply to every comment + follow back + invite friends" enough to grow a
   Page, or is outbound engagement required?** If outbound is required, what is
   the least-ban-prone way to do it without paid tools?
6. **How should the agent be scheduled and supervised** so it runs 24/7, paces
   itself like a human, stops on a warning from Meta, and never spends money?
7. **What would you refuse to automate, and why?**

Answer for a Page owner who will not pay for anything and cannot risk the
account. Be specific about rates, limits and stop conditions.
