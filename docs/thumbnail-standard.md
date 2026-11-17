# The thumbnail standard — the frame that decides the click

K (2026-11-17): "แม้กระทั่ง thumbnail ก็ต้องให้ได้มาตรฐาน 10/10". A thumbnail is not
decoration; it is the one image a scroller sees, so it is held to a measured floor
like every clip. `ops/thumb_standard.py` is the enforceable form; a below-floor
thumbnail cannot reach a channel because `ops/yt_publish.py` measures it before
`thumbnails.set`.

Everything is free (Rule #1): Pillow + numpy only.

## The floor

| Property | Floor |
| --- | --- |
| File size | ≤ 2 MB (YouTube's hard cap) |
| Width | ≥ 1280 (16:9 art) or ≥ 1080 (9:16 Short art) |
| Aspect | 16:9 or 9:16, ±2 % |
| Tonal range | p95 − p5 of luma ≥ 40 |
| Real detail | edge fraction ≥ 0.20 % |
| Title ink | bright pixels ≥ 0.10 % and ≤ 45 % |

Thresholds are calibrated from the 203 real thumbnails on disk, not invented. The
floor sits just under the 25th percentile, so it rejects a blank or failed render
without rejecting a legitimately dark, moody poster.

## Two lessons that set the thresholds

- **A dark poster is not a blank one.** The tonal-range floor is 40, not 100: a
  near-black render fails (range ~0) while a dark-but-real poster keeps its title
  and detail. The `dynamic_range_min` is what distinguishes "moody" from "failed".
- **A thin caption is still a title.** The bright-ink floor is 0.10 %, not 0.30 %.
  A short clip's Thai caption measures ~0.15 % of the frame; 0.30 % rejected every
  such Short as "no title". A blank frame measures ~0 %, so 0.10 % still catches
  a real failure.

## The gate

`ops/yt_publish.py::set_thumbnail(video_id, path, token)` measures the image
before the upload request and raises on a fail — the single chokepoint for all
four channels. A test asserts the gate runs before the upload.

## What the sweep found (2026-11-17)

Of 203 thumbnails, 20 failed at first. They were two real classes, not one:

- **Dark Short frames (12).** A Short's own frame is dark by construction — a
  blurred, scrimmed copy of the cover fills it, so the grab measured mean luma
  ~18 with no legible title. Fixed in `make_short.thumb_for`: the grab is lifted
  with `eq=gamma=1.6,unsharp=5:5:0.8`, which makes the caption read without
  touching the clip. The same lift was applied to the existing Short thumbs.
- **Low-contrast surreal posters (5).** The exhibit lane paints the cover through
  a recipe (`melt`/`wave`/`ghost`) that flattens the range to ~31. Fixed on the
  thumbnail with `eq=contrast=1.7:brightness=-0.08:saturation=1.1`; the clip art
  itself is a separate, larger question.
- **One oversized PNG (1).** A 1080×1920 poster over the 2 MB cap; re-saving as
  optimized RGB brought it to 1.7 MB.
- **Two were not thumbnails at all:** the square `1280×1280` covers are source
  art for the animated lanes, never uploaded as a YouTube thumbnail, so the
  aspect rule does not apply to them.

All 203 now pass. The lift is applied at render time in `thumb_for`, so a future
Short passes without a manual step; the surreal poster lift is a one-off on art
whose source is genuinely flat.

## Changing the standard

Raising a threshold is welcome. Lowering one to make a bad thumbnail pass is what
K forbade. If a rule is a false positive on real, correct art, fix the rule —
never the floor.
