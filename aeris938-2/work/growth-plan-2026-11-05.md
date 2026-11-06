# Growth plan — why the surfaces stalled, and what changes (2026-11-05)

Source: advisor panel of 2026-11-05, quorum 3/3 (duck, duck-claude, duck-oss).
Brief: `consult-brief-growth-stall-2026-11-05.md`. Log: `ops/consult-log.jsonl`.
The panel was asked to rank causes and give a free, script-executable plan.

## The verdict (unanimous)

1. **Most likely cause: (d) repetitive Shorts, then (a) weak hook.** 25 Shorts cut
   from 5 songs, all the same karaoke-chorus format, titled "part N of 3". Nothing
   distinguishes one upload from the next, so there is no reason to follow.
2. **The stalled TikTok and Facebook rails are a separate failure** — real, but
   they do not explain YouTube's view decline.
3. **Falling views are not evidence of duplicate-content suppression**, and the
   panel refused to call it that. Do not treat a dip as a penalty.
4. **6/day is not harmful, it is a bad test.** Six near-identical clips repeat one
   experiment instead of running six. Recommendation: **one distinct Short a day
   for 7 days**, compare, then raise volume only if the format is working.
5. **Quota correction:** the brief's "1,600 units per upload" is outdated.
   `videos.insert` has its own default bucket of **100 calls/day**, separate from
   the 10,000-unit pool. Quota is not a reason to post six times a day — nor to
   cut back. (Google quota docs; matches our own 2026-11-05 check.)
6. **Keep the lyric format; change the series and the clips.** A recurring,
   named format ("ร้องต่อไหม?" — "sing the next line?") with a *different*
   prompt each time. Original audio; trending audio only when it legitimately fits.
7. **One metric:** YouTube subscribers gained per 1,000 YouTube views (the only
   surface with readable view data). Test target: 10 net new followers in 7 days.
   Log TikTok/Facebook separately, never fold unreadable numbers in as zero.

## What shipped in code (this session)

| Change | File | Why |
| --- | --- | --- |
| Shorts rotate **across songs**, one hook per song per round | `release.py:plan()` | Three numbered parts of one song back to back read as one clip reposted |
| Per-hook **title + prompt** (`HOOK_TITLES`, `HOOK_ANGLES`) | `release.py` | Each clip needs its own answerable ask, not "part N" |
| Short title is `… | <series> #Shorts`, not "part N of 3" | `release.py:describe()` | Gives a reason to watch *this* clip |
| TikTok/FB captions use the same series + per-hook ask | `crosspost.py:caption()` | Keeps the three files of a song distinct on the surface that truncates |
| Affiliate card description reordered: **disclosure first, then a CTA to the profile link**, tracked URL as fallback | `release.py:describe_affiliate()` | A URL in a Short's description (or pinned comment) is **not tappable** — the advisor panel (3/3) said so; the clickable route is the channel profile link |
| Quota comments/messages corrected (100/day bucket, not 1,600 units) | `release.py`, `competitor_scan.py`, `ax-music-release.yml` | The old rule was simply wrong and steered the cadence |
| Regression tests: plan rotation, per-hook caption, link above the fold | `tests/run.py` | Each fix is pinned so it cannot silently revert |

Suite: **688 passed, 0 failed**. Queue captions refreshed in place (82 pending).

## The 7-day experiment (free, script-executable)

- **Cadence:** 6/day stays as the *upload* plan, but the queue now interleaves, so
  each day's song Shorts are six **different** songs. Day 1 leads with the five
  product cards (the affiliate lane had no content of its own).
- **Posting time:** test **19:00 Thailand time** for a week as a consistent
  experiment, not as a guaranteed best time.
- **Order:** upload the clean original to YouTube first, then post the same file
  natively to TikTok and Facebook. **Log that each post actually appears** — the
  expired sessions must not silently skip posting again.
- **Reply** to genuine comments with a relevant answer or a follow-up question.
- **Affiliate links stay out of the song captions' pitch**; the product cards carry
  the link (above the fold) and the mandatory disclosure.
- **Day 7:** compare views *and* follows per format. If views come but followers
  do not, the series' reason-to-follow is wrong. If views stay low, sharpen the
  opening and payoff **before** raising volume.

## Next levers, in order

1. Confirm the crosspost rail is actually posting (the "session died → step
   silently skipped" bug is the one that cost 44 TikTok posts before).
2. Give the other 10 songs their Shorts so the rotation has 15 songs to draw on,
   not 5.
3. Only after a format shows signal: raise cadence toward the 100/day ceiling.
