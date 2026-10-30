# AX channel dossiers — complete channel data

The full build sheet for each channel: identity, positioning, content pillars, the
episode formula, title and thumbnail rules, the description, keywords, playlists and
the first-30-days plan. Direction and goals come from `ops/AX_CHANNELS.md`; this file
is the detail that turns a direction into something publishable.

**State read from the live channels on 2026-10-24.** Nothing here is applied yet —
a channel rename or description change needs K's explicit approval.

## Branding state as found

| ch | title now | handle | language | keywords | description | banner |
| --- | --- | --- | --- | --- | --- | --- |
| ch1 | ตาต้า GenX Shop | `@tatagenxgeny` | *(unset)* | *(none)* | 118 chars, says "english เรื่อยเปื่อย ชิลๆ" | no |
| ch2 | Farmmer | `@farmmer-n9t` | **en** *(wrong)* | `lanternwild kids cartoon…` *(stale)* | 330 chars, correct dhamma | no |
| ch3 | AERIS Music | `@aerismusicth` | *(unset)* | *(none)* | 827 chars, **English only** | no |
| ch4 | kongkeat pratumma | `@kongkeatpratumma` | th | *(none)* | **empty** | no |

Three of the four need work: ch1's text contradicts its catalogue, ch2 has stale
keywords and the wrong language, ch3 is English-only on a Thai channel, ch4 is blank.

---

## ch1 — ช่องปรัชญา (life philosophy)

**Identity.** `UCI6EfsgM1HNjrYarvigxyrQ` · `@tatagenxgeny` · 76 videos · 6 subs.

**The problem to fix.** The name "ตาต้า GenX Shop" and the description
("english เรื่อยเปื่อย ชิลๆ สบายๆ ชีวิตประจำวัน อาหาร ละครสั้น คลิปสั้น") describe a
lifestyle/shop channel, but the catalogue is **"ปรัชญาชีวิต" philosophy talks at ~11
min**. A viewer who arrives from a philosophy video sees a shop name. Proposed:
`ตาต้า ปรัชญาชีวิต`, keeping the handle.

**Target viewer.** A Thai adult, 35+, who wants something calm to think along with —
commuting, working, or before sleep. Not a student; not looking for hype.

**Content pillars.** (1) everyday philosophy — a small idea made usable; (2) life
lessons from ordinary moments; (3) letting go and peace of mind; (4) encouragement for
a hard day. Pillar 1 is the backbone, as the catalogue already shows.

**Episode formula.** One idea per episode, ~11 min. Open with a plain question
("เคยรู้สึกไหมว่า…"), tell one story, draw one lesson, close gently. Never a list of
many ideas — that is what makes a talk feel long.

**Title formula.** A feeling, not a topic. `ปล่อยวาง แล้วใจจะเบา` beats
`เรื่องการปล่อยวาง`. Keep under 60 Thai characters.

**Thumbnail.** Low contrast, warm. One calm scene (open road, morning light, a cup, a
window) plus a short Thai phrase in large type, at most 5 words. Never a face reacting
— this channel is quiet. Match the reference's low contrast and moderate sharpness;
**never sharpen**.

**Description.** Thai, first line is the hook, then what the viewer gets, then 3
hashtags. The full text is in `ax_channels.json` -> `channels.ch1.branding.description`.

**Keywords.** `ปรัชญาชีวิต,ปรัชญา,ข้อคิดชีวิต,แง่คิด,มุมมองชีวิต,กำลังใจ,ใช้ชีวิต,ความสุข,
ความสงบ,คิดบวก,ปล่อยวาง,เติบโต,philosophy,life lessons,thai philosophy,wisdom,
mindfulness,self growth,calm,reflection`

**Playlists.** `ปรัชญาชีวิต` (the main series), `ข้อคิดก่อนนอน`, `กำลังใจวันแย่ ๆ`.

**First 30 days.** 20 episodes at ~11 min, one per day except Sundays. Reuse the
existing 76-video style exactly so the channel looks continuous. Fix the name and
description first — the catalogue is already good; the wrapper is what is wrong.

---

## ch2 — ช่องธรรมะก่อนนอน (dhamma before sleep)

**Identity.** `UCM3QO5L_pmj34n1JVlbhh-w` · `@farmmer-n9t` · 11 videos · 1 sub.
This is the **reference implementation** of the rail — copy it for the others.

**The problem to fix.** `defaultLanguage` is **`en`** on an all-Thai channel, and the
keywords still read `lanternwild kids cartoon animal stories kids songs` — leftovers
from content that was deleted. The description is already correct.

**Target viewer.** Someone in bed, phone dimmed, wanting to fall asleep. They are not
reading; they are listening. They must never be startled.

**Content pillars.** (1) คำสอนพระพุทธเจ้า; (2) บทสวด; (3) ปล่อยวาง/ความสงบ;
(4) เรื่องเล่าธรรมะสั้น. Keep every pillar calm — no pillar may raise the volume.

**Episode formula.** 10–12 min. Narration at a steady, slow pace; music bed that never
rises above the voice; no sudden cuts; no sound effects. The single goal is that the
listener is asleep before the end.

**Title formula.** `ธรรมะก่อนนอน — <the feeling>`. Example already working:
`ปล่อยวาง แล้วใจจะเบา`.

**Thumbnail.** Night, candle, lotus, mist, dawn. Dark but soft, low contrast. Short
Thai phrase. Never a bright or busy image — a bright thumbnail defeats the purpose.

**Description.** Already written and correct; keep it. See
`ax_channels.json` -> `channels.ch2.branding.description`.

**Keywords.** `ธรรมะก่อนนอน,ธรรมะ,ฟังธรรม,บทสวด,คำสอนพระพุทธเจ้า,ปล่อยวาง,สมาธิ,
นอนไม่หลับ,ผ่อนคลาย,ความสงบ,ข้อคิดชีวิต,กำลังใจ,dhamma,bedtime,buddhism,meditation,
thai dharma,relax,sleep,calm`

**Playlists.** `ธรรมะก่อนนอน`, `บทสวด`, `ปล่อยวาง ใจเบา`.

**First 30 days.** 25 episodes at 10–12 min, nightly. Fix the language and keywords
first, then publish on a fixed time so it becomes a bedtime habit.

---

## ch3 — ช่องสร้างศิลปินเพลง (build a music artist)

**Identity.** `UCm44BjAn03ruOF-WaA3ZRww` · `@aerismusicth` · 4 videos · 0 subs.
Live content: "NAVIYA — FIRST LIGHT", best video 232 views.

**The problem to fix.** The description is **English only** on a Thai channel.
Keywords and language are unset.

**The quota that sets the pace.** AiPASS gives **10 tracks per month**. Ten tracks is
exactly one artist's release — so the cadence is **one artist per month**, not more.
Plan the month around that number and never promise more.

**Target viewer.** Thai listeners 18–35 who follow an artist, not a genre. They come
back for the next song from the same voice.

**The artist formula.** Each month: pick the artist concept, write the 10 songs, build
a visual identity (portrait, palette, cover-art language), release one song at a time
with its own thumbnail. The **artist is the series** — songs are episodes.

**Song formula.** 3–4 min. Verse–chorus–verse–chorus–bridge–chorus. One hook repeated
at least 4 times. Title is the hook line.

**Thumbnail.** The artist's face or silhouette plus the song title. Consistent palette
across all 10 songs so the artist is recognisable at a glance in a feed.

**Description.** Thai, artist name first, then the song, then the release set, then
hashtags. Full text in `ax_channels.json` -> `channels.ch3.branding.description`.

**Keywords.** `เพลงไทย,เพลงใหม่,ศิลปินไทย,AERIS,เพลงเพราะ,เพลงฟังสบาย,เพลงอินดี้,
เพลงป็อป,music,thai music,thai artist,new music,indie pop`

**Playlists.** One per artist, named for the artist. `NAVIYA` exists already.

**First 30 days.** Finish artist #2: 10 tracks, one released every 3 days, each with
its own thumbnail. Match the loudness of the existing tracks (AiPASS arrives at
**-12 to -14 LUFS**), do not force it to -16.

---

## ch4 — ช่องละคร · การ์ตูนอะนิเมะ (drama and anime cartoon)

**Identity.** `UC7gCIu4G_7QCEJ8hJ-34zoQ` · `@kongkeatpratumma` · **empty**.
No name, description, keywords, language or banner. The handle is the account holder's
personal name — it is not a series brand.

**The decision K must make.** The series concept and name. Everything below depends on
it, so it is the only blocker.

**The quota that decides the method.** AiPASS video is **10 clips per month** at ~4.1 s
each — about **50 seconds of AI motion per month**. A 25-minute episode is ~1,500
seconds. So episode bodies can **never** be AI video; they are built from **AI stills +
ffmpeg motion**, with AI video reserved for hero shots and the title sequence.

**Target viewer.** Someone who follows a story. They come back because they want to
know what happens next — so continuity matters more than any single episode.

**The series formula (the part that makes it a series).**
1. **Character sheet first.** Appearance, outfit, palette, one signature detail. Lock
   it before shooting anything; this is what makes the character recognisable.
2. **Same style prompt and seed per character**, so scene stills look like one show.
3. **A story arc**, not standalone episodes: each episode ends on a question.
4. **Consistent open and close** — the same title card and outro every episode.

**Episode formula.** 10–25 min. Cold open (a hook in the first 10 seconds) → title card
→ 3–5 scenes → cliffhanger. Hero shot (AI video) at the open and at the cliffhanger.

**Title formula.** `EP.<n> — <what happens>`. Numbering is what makes it bingeable.

**Thumbnail.** The main character in a strong pose, one dramatic element, the episode
number. Same palette every episode so the series is recognisable in a feed.

**Description.** Not written — it depends on the series concept. Once the name is set,
write: series logline, this episode's summary, episode list, hashtags.

**Keywords (proposed).** `ละครไทย,การ์ตูน,อนิเมะ,ซีรี่ย์,การ์ตูนไทย,อนิเมะไทย,นิยายภาพ,
drama,thai drama,anime,animation,series,cartoon`

**Playlists.** One per series, in episode order.

**First 30 days.** Once K names the series: lock the character sheet, build episode 1
as a pilot at 10 min, then hold a fixed release day. Do not start publishing before
the character sheet is fixed — an inconsistent character cannot become a series.

---

## Rules that apply to all four

- **Audio first.** Build and measure the bed before any picture. Bed gain **0.34**; at
  0.9 the bed hits -14.8 LUFS against a -16.8 LUFS voice and every pause is louder than
  the speech. Target **-17 LUFS, true peak ≤ -1 dBFS**.
- **Never claim to have watched or heard anything.** Report measured numbers only.
- **AX does not upload.** K reviews first.
- **Never assume a duration.** Measure it, then add or cut.
- **Never reuse another channel's video files.** Ideas and free tools only.
- **Account rotation is forbidden.** A 403 quotaExceeded means that channel is capped.
- **A 30 s shell cap kills long ffmpeg** — run detached and poll the log.
- **Re-encode before upload**: crf 25 cut 499 MB to 166 MB at SSIM 0.970.
