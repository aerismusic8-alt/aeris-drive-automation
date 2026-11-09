#!/usr/bin/env python3
"""Render a vertical product Short for the Shopee affiliate funnel.

Why this exists. Every Short on the channel so far is a song, and a song gives a
viewer no reason to buy anything — the affiliate link sat in a caption where
nobody was about to purchase, so the reported clicks were 0. A revenue funnel
needs content whose *intent* is a purchase: a product card with a hook, three
honest bullet points, a price and a link. This builds that card as a 9:16 clip
bedded on an AERIS song, so the same audience engine carries it.

It is deliberately not a video of the product. We have not tested the products,
so the clip shows the listing's own image and the listing's own facts, and it
says so — claiming a first-hand review we cannot back would breach Shopee's
terms and Thai advertising law (see aeris938-2/COMPLIANCE.md).

    python3 scripts/make_affiliate_short.py --plan
    python3 scripts/make_affiliate_short.py --all
    python3 scripts/make_affiliate_short.py hp-budget-01

Products live in `work/affiliate-products.json` (see PRODUCTS_SHAPE below).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_karaoke import FONT, OUTLINE, ass_filter  # noqa: E402
from make_short import _pick_window, thumb_for  # noqa: E402

PRODUCTS = ROOT / "work" / "affiliate-products.json"
LIBRARY = ROOT / "library"
AFF_DIR = LIBRARY / "affiliate"
SONGS = LIBRARY / "songs"
COVERS = LIBRARY / "covers"

W, H, FPS = 1080, 1920, 30
MAX_SECONDS = 58.0

# PRODUCTS_SHAPE = a JSON object {"products": [ {...} ]} where each product is:
#   id       stable slug, used for the output filename and the post id
#   title    the card hook, e.g. "หูฟังบลูทูธราคาประหยัด"
#   bullets  2-4 buying-guidance points (general advice, not a product claim)
#   song     slug of the AERIS song to bed it on
#   hook     which chorus to use (1-based)
#   image    optional path to a product photo; the song cover is used if absent
#   price    optional display price; only set it from a listing you have read
#
# The affiliate link is NOT stored per product: it is resolved per *surface*
# through `monetize.link()`, so a sale is attributed to the app it came from
# (the Sub_id in the s.shopee.co.th link). Storing one link on the card would
# lose that attribution.

# Over-claims that breach Shopee affiliate terms and Thai advertising law. A
# card carrying any of these is refused rather than rendered, because a banned
# claim is a channel-level risk for a commission of a few baht.
BANNED_CLAIMS = (
    "รวยแน่นอน", "รวย", "กำไร", "ผลตอบแทน", "ลงทุน", "การันตีรวย",
    "100%", "ฟรี100", "แน่นอนที่สุด", "ดีที่สุดในโลก",
)

DISCLOSURE = "ลิงก์พันธมิตร Shopee — เราอาจได้ค่าคอมมิชชัน"


def load_products() -> list[dict]:
    if not PRODUCTS.exists():
        return []
    return json.loads(PRODUCTS.read_text(encoding="utf-8")).get("products", [])


def claim_problem(product: dict) -> str | None:
    """Return the offending phrase if the card makes a banned claim, else None."""
    blob = " ".join([product.get("title", "")] + list(product.get("bullets", [])))
    for phrase in BANNED_CLAIMS:
        if phrase in blob:
            return phrase
    return None


def _link_ok(url: str) -> bool:
    return bool(re.match(r"https://s\.shopee\.co\.th/\w+", url or ""))


def link_for(platform: str) -> str:
    """This surface's Shopee affiliate link (carries the surface in Sub_id)."""
    import monetize  # noqa: PLC0415  local: keeps the module import-light
    return monetize.link(platform)


def caption(product: dict, platform: str = "tiktok") -> str:
    """A caption that leads with the product, discloses, and carries its link.

    The link is the *surface's* tracking link, so a sale is attributed to the
    app it came from. The disclosure line is mandatory (COMPLIANCE.md).
    """
    title = product["title"]
    price = product.get("price", "")
    bullets = " · ".join(product.get("bullets", [])[:2])
    url = link_for(platform)
    head = f"{title} {price}".strip()
    # The hashtag is the card's real search query, not the old `#ของน่าซื้อ` —
    # a Google Suggest pull (2026-11-09) showed that term is a souvenir/gift
    # query, so it sent the funnel to nobody who was shopping for audio gear.
    stag = "#" + product.get("search", "หูฟังบลูทูธ").replace(" ", "")
    if platform == "facebook":
        return (f"{head}\n{bullets}\n"
                f"🛒 ดูราคา/สั่งซื้อ 👉 {url}\n"
                f"⚠️ {DISCLOSURE}\n"
                f"🎬 เพลงประกอบจาก AERIS Music · YouTube @aerismusicth\n"
                f"{stag} #หูฟังบลูทูธ #Shopee #AERISMusic")
    if platform == "youtube":
        return (f"{head}\n{bullets}\n"
                f"🛒 ลิงก์สินค้า 👉 {url}\n"
                f"⚠️ {DISCLOSURE}\n"
                f"🎵 เพลงจาก AERIS Music\n"
                f"{stag} #หูฟังบลูทูธ #Shopee #AERISMusic")
    return (f"{head}\n{bullets}\n"
            f"🛒 กดลิงก์ 👉 {url}\n"
            f"⚠️ {DISCLOSURE}\n"
            f"🎵 เพลงจาก AERIS Music\n"
            f"{stag} #หูฟังบลูทูธ #Shopee #AERISMusic")


def _esc(text: str) -> str:
    return (text.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}")
            .replace("\n", r"\N"))


def build_ass(product: dict, seconds: float) -> str:
    """The card's text layer: hook, bullets, price, disclosure, CTA.

    Every line is placed with an explicit `\\pos` at `\\an5` (centre anchor).
    Letting libass stack them by style does not work here: five styles that
    share an alignment and margin all draw on the same line and overprint. The
    card's job is to be readable at a glance, so the vertical order is fixed:
    hook, price, bullets down the middle, CTA and the disclosure band at the
    foot, where the video is dimmed to hold them.
    """
    # The opening line is the scroll-stopper, not the topic: Shorts are decided
    # in the first 3 seconds, so lead with the benefit or the question.
    hookline = _esc(product.get("hookline") or product["title"])
    bullets = [_esc(b) for b in product.get("bullets", [])[:3]]
    price = _esc(product.get("price", ""))

    def pos(x: int, y: int) -> str:
        return f"{{\\an5\\pos({x},{y})}}"

    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {W}
PlayResY: {H}
WrapStyle: 2
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Hook,{FONT},72,&H00FFFFFF,&H00FFFFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,0.4,0,1,5,3,2,60,60,60,1
Style: Bullet,{FONT},46,&H00F0FFFF,&H00F0FFFF,{OUTLINE},&H80000000,1,0,0,0,100,100,0.4,0,1,4,2,2,60,60,60,1
Style: Price,{FONT},88,&H0000E0FF,&H0000E0FF,{OUTLINE},&H80000000,1,0,0,0,100,100,0.5,0,1,6,3,2,60,60,60,1
Style: Note,{FONT},36,&H00CCCCCC,&H00CCCCCC,{OUTLINE},&H80000000,0,0,0,0,100,100,0.3,0,1,3,1,2,60,60,60,1
Style: Cta,{FONT},56,&H0000FF88,&H0000FF88,{OUTLINE},&H80000000,1,0,0,0,100,100,0.4,0,1,5,2,2,60,60,60,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    def ts(t: float) -> str:
        t = max(0.0, t)
        return f"{int(t // 3600)}:{int(t % 3600 // 60):02d}:{t % 60:05.2f}"

    # Vertical bands. The product image occupies the top ~45%; the text lives on
    # the dimmed lower half so it never fights the cover art.
    y_hook, y_price = 1010, 1130
    y_bullets = [1250, 1330, 1410]
    y_cta, y_note = 1640, 1790

    ev: list[str] = []
    ev.append(f"Dialogue: 0,{ts(0)},{ts(seconds)},Hook,,0,0,0,,"
              f"{pos(540, y_hook)}{{\\fad(150,150)}}{hookline}")
    if price:
        ev.append(f"Dialogue: 0,{ts(0.5)},{ts(seconds)},Price,,0,0,0,,"
                  f"{pos(540, y_price)}{{\\fad(150,150)}}{price}")
    for b, y in zip(bullets, y_bullets):
        ev.append(f"Dialogue: 0,{ts(2.6)},{ts(seconds)},Bullet,,0,0,0,,"
                  f"{pos(540, y)}{{\\fad(140,140)}}• {b}")
    ev.append(f"Dialogue: 0,{ts(1.6)},{ts(seconds)},Cta,,0,0,0,,"
              f"{pos(540, y_cta)}{{\\fad(150,150)}}» กดลิงก์ด้านล่าง")
    ev.append(f"Dialogue: 0,{ts(1.0)},{ts(seconds)},Note,,0,0,0,,"
              f"{pos(540, y_note)}{_esc(DISCLOSURE)}")
    return head + "\n".join(ev) + "\n"


def _image_for(product: dict) -> Path:
    img = product.get("image")
    if img:
        p = (ROOT / img) if not Path(img).is_absolute() else Path(img)
        if p.exists():
            return p
    cover = COVERS / f"cover-{product['song']}.jpg"
    if cover.exists():
        return cover
    raise FileNotFoundError(
        f"no image for {product['id']}: set `image` or provide a cover for "
        f"song {product['song']}")


def render(product: dict, out_dir: Path | None = None) -> Path:
    problem = claim_problem(product)
    if problem:
        raise SystemExit(f"{product['id']}: banned claim {problem!r} — fix the card")
    # Validate every surface link up front so a bad link is caught at render
    # time, not after a clip has been posted with a dead link in it.
    for surface in ("tiktok", "facebook", "youtube"):
        if not _link_ok(link_for(surface)):
            raise SystemExit(
                f"{product['id']}: no affiliate link for {surface} "
                f"(check shopee_links in channel/monetization.json)")

    audio = SONGS / f"song-{product['song']}.mp3"
    if not audio.exists():
        raise FileNotFoundError(f"missing {audio}")
    image = _image_for(product)

    # Reuse make_short's chorus picker so the bed is the hook, not the intro.
    from make_karaoke import _duration  # noqa: E402
    dur = _duration(audio)
    start, length = _pick_window(product["song"], dur)
    length = min(length, MAX_SECONDS)

    work = ROOT / "work" / "affiliate"
    work.mkdir(parents=True, exist_ok=True)
    ass_path = work / f"aff-{product['id']}.ass"
    ass_path.write_text(build_ass(product, length), encoding="utf-8")

    out_dir = out_dir or AFF_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"short-aff-{product['id']}.mp4"

    cw = int(W * 0.92)
    cy = int(H * 0.06)
    chain = (
        f"[0:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},"
        f"gblur=sigma=30,eq=brightness=-0.10:saturation=1.05[bg];"
        f"[0:v]scale={cw}:-1[fg];"
        f"[bg][fg]overlay=(W-w)/2:{cy}[base];"
        f"[base]drawbox=x=0:y={int(H*0.60)}:w={W}:h={int(H*0.40)}:"
        f"color=black@0.42:t=fill[scrimd];"
        f"[scrimd]{ass_filter(ass_path)}[v]"
    )
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error",
         "-loop", "1", "-i", str(image),
         "-ss", f"{start:.3f}", "-i", str(audio),
         "-filter_complex", chain,
         "-map", "[v]", "-map", "1:a",
         "-t", f"{length:.3f}",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
         "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "192k", "-shortest",
         "-movflags", "+faststart", str(out)],
        check=True)
    thumb_for(out, image)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("product", nargs="?", help="product id")
    ap.add_argument("--all", action="store_true", help="every product in the file")
    ap.add_argument("--plan", action="store_true", help="show what would render")
    args = ap.parse_args()

    products = load_products()
    if not products:
        print(f"no products in {PRODUCTS.relative_to(ROOT)} — add cards first")
        return 1
    if args.product:
        products = [p for p in products if p["id"] == args.product]
        if not products:
            print(f"no product with id {args.product}")
            return 1

    if args.plan:
        for p in products:
            bad = claim_problem(p)
            state = f"REFUSED ({bad})" if bad else "ok"
            print(f"{p['id']:20} {state:24} {p['title'][:40]}")
        return 0

    for p in products:
        out = render(p)
        print(f"{p['id']}: {out.relative_to(ROOT)}")
        print(f"  caption(tiktok): {caption(p, 'tiktok').splitlines()[0]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
