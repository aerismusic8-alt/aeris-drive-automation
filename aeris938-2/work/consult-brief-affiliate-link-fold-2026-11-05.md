# Brief: the Shopee affiliate link sits below YouTube's "Show more" fold

## Context
Channel `@aerismusicth` (music938-1) is releasing 5 product-card Shorts/day for
the Shopee affiliate funnel. Each card's YouTube description is built by
`release.describe_affiliate()`. On YouTube the description shows ~2 lines before
"Show more". The current description is:

```
<hookline>
<blank>
• bullet 1
• bullet 2
• bullet 3
🛒 ลิงก์สินค้า 👉 https://s.shopee.co.th/8pn3G4alfI
⚠️ ลิงก์พันธมิตร Shopee — เราอาจได้ค่าคอมมิชชัน
🎵 เพลงจาก AERIS Music — ค่ายเพลง AI

#ของน่าซื้อ #หูฟัง #Shopee #AERISMusic #Shorts
```

So the affiliate link is on line 6 — below the fold. The docstring claims it sits
"above the fold" but it does not. (A separate pinned comment carries a tappable
link, but pinning needs a signed-in browser session that is currently dead.)

## The question
1. For a 9:16 Short where the description is mostly hidden behind "Show more",
   what is the highest-converting honest layout for a Shopee affiliate link?
   Is "hookline then link on line 2, bullets after" right, or is there a better
   order given that the video itself already shows the hook + bullets on screen?
2. Should the Shopee link be a bare URL, a `▶ ดูราคา/สั่งซื้อ 👉` CTA line, or is
   there a platform rule (YouTube/Shopee) against either?
3. Any YouTube policy risk in repeating the affiliate link both in the Short's
   description and (later) a pinned comment?

## Constraints
- Thai audience, Thai text. Free tools only. No first-hand product claims.
- COMPLIANCE.md requires the affiliate disclosure on every card.
- The link must stay the tracked `s.shopee.co.th/...` short link (sub_id =
  surface) for attribution.
