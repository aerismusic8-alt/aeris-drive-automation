"""The channel's brand identity, in one place.

K renamed the channel to **NEO VINCI** on 2026-11-16 (the YouTube handle stays
`@aerismusicth`). The name carries the positioning: a modern-da Vinci label that
fuses the classic art of songwriting with modern AI technology.

Every surface that shows or speaks the brand reads from here — the burned-in
video marks, the cover-art mark, the banner/avatar, the titles, the descriptions
and the hashtags — so a rename is one edit, not thirty. The old literal
"AERIS MUSIC" scattered across the scripts is what made this rebrand expensive;
keep the name out of the call sites.
"""
from __future__ import annotations

NAME = "NEO VINCI"
# The wordmark is set in caps on art; the spoken/typed form keeps the spaces.
TAGLINE = "ศิลปะคลาสสิก ผสานเทคโนโลยีล้ำสมัย"
POSITIONING = "ดาวินชีแห่งยุคใหม่"

# The channel description, shared by the channel branding and the profile setup.
DESCRIPTION = (
    "NEO VINCI — ดาวินชีแห่งยุคใหม่ รวมเพลงไทยที่ผสานความคลาสสิกของศิลปะ "
    "เข้ากับเทคโนโลยีล้ำสมัย เพลงใหม่ทุกวัน"
)

# The YouTube handle did not change with the name.
HANDLE = "@aerismusicth"
CHANNEL_URL = f"https://www.youtube.com/{HANDLE}"

# Hashtags carry the brand. The old #AERISMusic is retired; the handle tag stays
# so the two are not confused for different channels.
HASHTAG = "#NEOVINCI"
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
