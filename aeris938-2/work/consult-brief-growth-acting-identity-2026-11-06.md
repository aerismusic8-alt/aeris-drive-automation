# Brief: the "follow suggested pages" growth loop silently follows as the personal profile

Context: a free growth loop for a Facebook Page (AERIS Music, id 61595890900382)
opens `https://www.facebook.com/pages/?category=invite&page_id=<id>` and clicks
"ติดตาม" (Follow) on suggested pages. Facebook only attributes a follow to the
Page when the **Page is the acting identity**; otherwise the follow lands on the
personal profile and the Page gains nothing.

Observed today: `_acting_as_page()` returned True but the Page's "กำลังติดตาม"
count did not move after two follows. Inspecting the live DOM: the page URL is
`facebook.com/people/AERIS-Music/61595890900382/` and the header contains the
banner "สลับไปใช้เพจ AERIS Music เพื่อดำเนินการเพิ่มเติม" with a "สลับ" button —
i.e. we are viewing the Page **as the personal profile**, not acting as it.

Root cause found: `_acting_as_page()` tests `"จัดการเพจ" in body`. But
"จัดการเพจ" also appears in the *personal* profile's left rail (the menu entry
that lists pages you manage), so the check is a false positive and the switch is
never attempted.

Questions:
1. What is the most reliable DOM/text signal that the Page — not the personal
   profile — is the acting identity on current facebook.com? Is "the switch
   banner is absent" a sound test, or is there a more stable anchor?
2. The switch is clicked via `get_by_text("สลับ", exact=True)`. Is clicking that
   banner button enough, or does Facebook require the Page-profile switcher
   (the avatar menu) and a confirmation? Any known trap where the click appears
   to work but the identity reverts on navigation?
3. Is there a more durable route to follow *as the Page* at all — e.g. the
   Meta Business Suite surface, or the Page's own "Pages you follow" tools —
   that does not depend on the personal-profile shell's switch banner?
4. How should the code verify success before it clicks any Follow, so a
   false-positive can never let a follow land on the personal profile?

Answer concretely; assume the only tool is a signed-in headful Chromium over CDP.
