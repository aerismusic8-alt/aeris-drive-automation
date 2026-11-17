"""The channel's brand identity, in one place.

K set the channel's live display name to **เพลงส้นทีนไรเนี่ย** (YouTube shows it
on `@aerismusicth`; the handle did not change). The name is Thai, so every mark
that draws it must use the bundled Thai font — the Latin wordmark font renders it
as tofu.

Every surface that shows or speaks the brand reads from here — the burned-in
video marks, the cover-art mark, the banner/avatar, the titles, the descriptions
and the hashtags — so a rename is one edit, not thirty. The old literals
("AERIS MUSIC", then "NEO VINCI") scattered across the scripts are what made each
rebrand expensive; keep the name out of the call sites.
"""
from __future__ import annotations

NAME = "เพลงส้นทีนไรเนี่ย"
# The wordmark is drawn on art; the spoken/typed form is the same string.
POSITIONING = "เพลงไทยใหม่ทุกวัน"
TAGLINE = "ป็อป · แดนซ์ · ร็อก · เพลงเศร้า · ให้กำลังใจ"

# The channel description, shared by the channel branding and the profile setup.
DESCRIPTION = (
    f"{NAME} — เพลงไทยใหม่ทุกวัน รวมเพลงไทยป็อป แดนซ์ ร็อก เพลงเศร้า "
    "และเพลงให้กำลังใจ เนื้อร้องและทำนองใหม่ สร้างด้วย AI"
)

# The YouTube handle did not change with the name.
HANDLE = "@aerismusicth"
CHANNEL_URL = f"https://www.youtube.com/{HANDLE}"

# Hashtags carry the brand. The retired #AERISMusic and #NEOVINCI are dropped;
# the handle tag stays so the two are not confused for different channels.
HASHTAG = f"#{NAME}"
HASHTAGS = f"{HASHTAG} #เพลงไทย #ศิลปินไทย #เพลงใหม่ #เพลงป็อป #เพลงแดนซ์ #เพลงร็อก"

# The honest AI-label line every description carries (K, 2026-11-04: say it
# plainly). The songs and the vocals are AI-generated; the copy must not claim
# otherwise.
LABEL = f"🤖 {NAME} — ค่ายเพลง AI สร้างเพลงและเสียงร้องด้วย AI"

# The follow ask burned onto the end of every Short. Text only, no emoji: the
# burned-in font is Noto Sans Thai, which has no emoji glyph and renders tofu.
FOLLOW_ASK = f"กดติดตาม {NAME}"
FOLLOW_PROMISE = "เพลงใหม่ทุกวัน"


def credit_line() -> str:
    """One line naming the brand and its channel, for captions and credits."""
    return f"{NAME} · {CHANNEL_URL}"
