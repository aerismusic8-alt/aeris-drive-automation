#!/usr/bin/env python3
"""Render a clip whose picture is driven by the song, not a still with a zoom.

K (2026-11-18): "ทำเป็นอีควอไลเซอร์ตามจังหวะเพลงได้ไหม หรือทำตัวการ์ตูนเต้นตาม
จังหวะ ... ไม่ใช่ทำภาพนิ่งแล้วก็เอาภาพมาสั่น" — the picture must move *with the
music*. So the picture here is computed from the audio:

  * a **radial equalizer** — 64 log-spaced bands of the real spectrum, drawn as
    bars around the mascot, so the bass kicks the bottom and the hats flicker;
  * a **mascot that dances** — an original character drawn in code (no licence,
    no asset), bouncing, squashing and tilting on the detected onsets, with a
    mouth that opens on the vocal energy so it reads as singing along;
  * **beat effects** — a punch flash and a frame shake on a strong onset.

Everything is measured from the file's own audio (numpy STFT), so the motion is
the song's motion, not a fixed wobble. The lyrics come from the master's own
subtitle track, never an estimate.

The render is piped frame-by-frame into ffmpeg and gated by `clip_standard`, so a
below-floor clip is deleted instead of published.

    python3 ops/make_reactive.py --src master.mp4 --slug x --title "X" \
        --mode reel --out out.mp4            # 1080x1920, <= 88 s
    python3 ops/make_reactive.py --src master.mp4 --slug x --title "X" \
        --mode full --out out.mp4            # 1920x1080, whole track
"""
from __future__ import annotations

import argparse
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))
from song_to_page import _tool, duration, extract_srt, parse_srt  # noqa: E402

MUSIC = ROOT / "music938-1"
FONT_PATH = MUSIC / "fonts" / "NotoSansThai.ttf"

FPS = 30
BARS = 64
# A bright, cheerful rainbow (cyan -> green -> yellow -> orange -> pink). K
# (2026-11-18): "ทำสีสว่างสดใสเลยช่องเราไม่มืดมัว" — the channel is not a dark
# one, so no deep-purple-to-black ramp; every bar is a saturated bright hue.
RAMP = [(40, 230, 255), (70, 255, 150), (255, 240, 70), (255, 150, 40), (255, 90, 190)]


def _lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def ramp(t: float):
    t = min(1.0, max(0.0, t)) * (len(RAMP) - 1)
    i = int(t)
    return _lerp(RAMP[i], RAMP[min(i + 1, len(RAMP) - 1)], t - i)


# ---------------------------------------------------------------------------
# Audio -> per-frame envelopes
# ---------------------------------------------------------------------------
def analyze(src: Path, fps: int = FPS) -> dict:
    sr = 22050
    wav = tempfile.mktemp(suffix=".f32")
    subprocess.run([_tool("ffmpeg"), "-v", "error", "-y", "-i", str(src),
                    "-ac", "1", "-ar", str(sr), "-f", "f32le", wav], check=True)
    x = np.fromfile(wav, dtype=np.float32)
    os.unlink(wav)
    win = 2048
    hop = int(sr / fps)
    frames = np.lib.stride_tricks.sliding_window_view(x, win)[::hop]
    spec = np.abs(np.fft.rfft(frames * np.hanning(win), axis=1))  # n x 1025
    freqs = np.fft.rfftfreq(win, 1 / sr)
    edges = np.geomspace(30, min(12000, sr / 2 - 1), BARS + 1)
    bands = np.empty((spec.shape[0], BARS), np.float32)
    for b in range(BARS):
        idx = np.where((freqs >= edges[b]) & (freqs < edges[b + 1]))[0]
        bands[:, b] = spec[:, idx].mean(axis=1) if len(idx) else 0.0
    for b in range(BARS):                       # each band on its own 0..1 scale
        bands[:, b] = np.clip(bands[:, b] / (np.percentile(bands[:, b], 95) + 1e-9), 0, 1)

    def smooth(a, k):
        return np.convolve(a, np.ones(k) / k, mode="same")

    bass = smooth(bands[:, :12].mean(1), 3)
    mid = smooth(bands[:, 12:40].mean(1), 3)
    high = smooth(bands[:, 40:].mean(1), 2)
    vocal = smooth(bands[:, 14:46].mean(1), 5)  # the mouth follows this
    flux = np.concatenate([[0.0], np.maximum(0, np.diff(bands, axis=0)).sum(1)])
    flux = np.clip(flux / (np.percentile(flux, 98) + 1e-9), 0, 1)
    punch = np.zeros(len(flux), np.float32)     # spikes on an onset, decays
    for i in range(len(flux)):
        punch[i] = max(flux[i], punch[i - 1] * 0.82 if i else 0.0)
    return dict(bands=bands, bass=bass, mid=mid, high=high, vocal=vocal,
                flux=flux, punch=punch, dur=len(x) / sr)


# ---------------------------------------------------------------------------
# The mascot — an original character, drawn in code
# ---------------------------------------------------------------------------
def draw_mascot(size: int, mouth: float = 0.0) -> Image.Image:
    """Orange squishy robot with a cheeky face. `mouth` 0..1 opens the mouth."""
    S = size
    u = S / 900.0
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cy = S // 2

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([cx - 380 * u, cy - 380 * u, cx + 380 * u, cy + 380 * u],
                                 fill=(255, 150, 40, 110))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60 * u)))

    bw, bh = 520 * u, 560 * u
    top, bot = cy - bh / 2 + 40 * u, cy + bh / 2 + 40 * u
    # antenna first, so the body sits over its base
    d.line([cx, top, cx, top - 150 * u], fill=(255, 200, 90, 255), width=int(16 * u))
    d.ellipse([cx - 48 * u, top - 230 * u, cx + 48 * u, top - 134 * u],
              fill=(80, 230, 255, 255), outline=(255, 255, 255, 255), width=int(6 * u))
    # arms
    for sx in (-1, 1):
        ax = cx + sx * (bw / 2 + 70 * u)
        d.rounded_rectangle([ax - 62 * u, cy - 70 * u, ax + 62 * u, cy + 40 * u],
                            radius=52 * u, fill=(255, 138, 32, 255),
                            outline=(255, 200, 90, 255), width=int(8 * u))
    # body + belly
    d.rounded_rectangle([cx - bw / 2, top, cx + bw / 2, bot], radius=190 * u,
                        fill=(255, 138, 32, 255), outline=(255, 200, 90, 255),
                        width=int(10 * u))
    d.ellipse([cx - 150 * u, cy + 60 * u, cx + 150 * u, cy + 240 * u],
              fill=(255, 215, 140, 255))
    # eyes: left wide, right winking — the cheeky face
    lx, rx = cx - 118 * u, cx + 118 * u
    d.ellipse([lx - 74 * u, cy - 130 * u, lx + 74 * u, cy + 18 * u], fill=(255, 255, 255, 255))
    d.ellipse([lx - 36 * u, cy - 76 * u, lx + 36 * u, cy + 8 * u], fill=(40, 30, 25, 255))
    d.ellipse([lx - 10 * u, cy - 62 * u, lx + 20 * u, cy - 30 * u], fill=(255, 255, 255, 255))
    d.arc([rx - 74 * u, cy - 110 * u, rx + 74 * u, cy + 20 * u], 200, 340,
          fill=(40, 30, 25, 255), width=int(16 * u))
    # mouth: a grin that opens into a singing O
    mw = 96 * u * (1 + 0.7 * mouth)
    mh = 26 * u + 150 * u * mouth
    d.ellipse([cx - mw, cy + 120 * u - mh / 2, cx + mw, cy + 120 * u + mh / 2],
              fill=(90, 25, 30, 255), outline=(60, 15, 20, 255), width=int(6 * u))
    if mouth > 0.25:
        d.ellipse([cx - mw * 0.5, cy + 120 * u + mh * 0.15, cx + mw * 0.5,
                   cy + 120 * u + mh * 0.6], fill=(255, 110, 130, 255))
    # feet
    for sx in (-1, 1):
        fx = cx + sx * 95 * u
        d.rounded_rectangle([fx - 65 * u, bot - 40 * u, fx + 65 * u, bot + 40 * u],
                            radius=35 * u, fill=(230, 110, 20, 255))
    return im


# ---------------------------------------------------------------------------
# Frame composition
# ---------------------------------------------------------------------------
class Scene:
    def __init__(self, src: Path, mode: str, cues, start: float, length: float,
                 title: str, brand_ask: str, brand_promise: str):
        self.mode = mode
        self.cues = cues
        self.start = start
        self.length = length
        self.title = title
        self.brand_ask = brand_ask
        self.brand_promise = brand_promise
        if mode == "reel":
            self.W, self.H = 1080, 1920
            self.cx, self.cy, self.r0, self.rmax = 540, 700, 340, 200
            self.mascot = 620
            self.lyric_y = 1520
            self.lyric_size = 54
        else:
            self.W, self.H = 1920, 1080
            self.cx, self.cy, self.r0, self.rmax = 700, 500, 290, 190
            self.mascot = 520
            self.lyric_y = 760
            self.lyric_size = 50
        self.cover = self._cover(src)
        self.bg = self._bg(self.cover)
        self.mascots = [draw_mascot(self.mascot, m) for m in (0.0, 0.25, 0.5, 0.75, 1.0)]
        self.font = ImageFont.truetype(str(FONT_PATH), self.lyric_size)
        self.font_big = ImageFont.truetype(str(FONT_PATH), int(self.lyric_size * 1.25))
        self._lyric_cache: dict[str, Image.Image] = {}

    def _cover(self, src: Path) -> Image.Image:
        png = Path(tempfile.mktemp(suffix=".png"))
        subprocess.run([_tool("ffmpeg"), "-v", "error", "-y", "-i", str(src),
                        "-frames:v", "1", str(png)], check=True)
        im = Image.open(png).convert("RGB")
        os.unlink(png)
        return im

    def _bg(self, cover: Image.Image) -> Image.Image:
        scale = max(self.W / cover.width, self.H / cover.height)
        big = cover.resize((int(cover.width * scale) + 1, int(cover.height * scale) + 1))
        left = (big.width - self.W) // 2
        top = (big.height - self.H) // 2
        bg = big.crop((left, top, left + self.W, top + self.H))
        bg = bg.filter(ImageFilter.GaussianBlur(34))
        # Bright, not dim: the channel is "ไม่มืดมัว". Lift the blurred cover into a
        # sunny range and lay a soft light gradient over it so nothing reads dark.
        bg = bg.point(lambda v: min(255, int(120 + v * 0.62)))
        grad = Image.new("L", (1, self.H))
        for y in range(self.H):
            grad.putpixel((0, y), int(70 * (1 - y / self.H)))
        veil = Image.new("RGBA", (self.W, self.H), (255, 255, 255, 255))
        veil.putalpha(grad.resize((self.W, self.H)))
        bg = bg.convert("RGBA")
        bg.alpha_composite(veil)
        return bg

    def lyric_img(self, text: str) -> Image.Image:
        if text in self._lyric_cache:
            return self._lyric_cache[text]
        pad = 24
        tmp = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
        box = tmp.textbbox((0, 0), text, font=self.font, stroke_width=6)
        im = Image.new("RGBA", (box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2),
                       (0, 0, 0, 0))
        ImageDraw.Draw(im).text((pad - box[0], pad - box[1]), text, font=self.font,
                                fill=(255, 255, 255, 255), stroke_width=6,
                                stroke_fill=(20, 10, 30, 235))
        self._lyric_cache[text] = im
        return im

    def active_lyric(self, t: float) -> str:
        for st, en, txt in self.cues:
            if self.start + t >= st and self.start + t < en:
                return txt
        return ""

    def frame(self, t: float, bands, bass, vocal, punch) -> Image.Image:
        W, H = self.W, self.H
        im = self.bg.copy()
        d = ImageDraw.Draw(im, "RGBA")

        # radial equalizer behind the mascot — thick, bright bars so it reads as
        # an equalizer on a phone screen, with a soft glow under each one
        for i in range(BARS):
            ang = 2 * math.pi * i / BARS - math.pi / 2
            e = float(bands[i])
            r1 = self.r0
            r2 = self.r0 + 30 + self.rmax * e
            x1, y1 = self.cx + r1 * math.cos(ang), self.cy + r1 * math.sin(ang)
            x2, y2 = self.cx + r2 * math.cos(ang), self.cy + r2 * math.sin(ang)
            col = ramp(0.45 + 0.55 * e)
            d.line([(x1, y1), (x2, y2)], fill=col + (120,), width=22)
            d.line([(x1, y1), (x2, y2)], fill=(255, 255, 255, 90 + int(120 * e)),
                   width=7)
        # a pulsing halo ring, driven by the bass
        halo = int(self.r0 - 30 - 26 * float(bass))
        d.ellipse([self.cx - halo, self.cy - halo, self.cx + halo, self.cy + halo],
                  outline=(255, 210, 120, int(120 + 120 * float(bass))), width=10)

        # the mascot: bounce up on a hit, squash on landing, tilt side to side
        p = float(punch)
        bounce = -70 * p
        squash = 1 + 0.14 * p
        tilt = 7.0 * math.sin(2 * math.pi * t * 0.9) * (0.4 + 0.6 * p)
        mouth = min(1.0, float(vocal) * 1.3)
        sprite = self.mascots[min(4, int(mouth * 4.999))]
        mw = int(self.mascot / squash)
        mh = int(self.mascot * squash)
        sp = sprite.resize((mw, mh))
        sp = sp.rotate(tilt, resample=Image.BICUBIC, expand=True)
        im.alpha_composite(sp, (int(self.cx - sp.width / 2),
                                int(self.cy + bounce - sp.height / 2)))

        # beat flash + confetti burst, so a strong hit reads as a party
        if p > 0.05:
            flash = Image.new("RGBA", (W, H), (255, 90, 130, int(60 * p)))
            im.alpha_composite(flash)
        if p > 0.45:
            rng = np.random.default_rng(int(t * FPS))
            n = int(18 * (p - 0.45) / 0.55) + 4
            xs = rng.integers(0, W, n)
            ys = rng.integers(int(self.cy - 320), int(self.cy + 320), n)
            cols = [(255, 215, 90), (80, 230, 255), (255, 90, 160), (140, 255, 140)]
            for j in range(n):
                r = int(6 + 10 * rng.random())
                c = cols[j % len(cols)]
                d.ellipse([xs[j] - r, ys[j] - r, xs[j] + r, ys[j] + r],
                          fill=c + (int(200 * p),))

        # lyrics, from the master's own track
        end_card = self.length - 3.0
        if t < end_card:
            line = self.active_lyric(t)
            if line:
                li = self.lyric_img(line)
                im.alpha_composite(li, ((W - li.width) // 2,
                                        self.lyric_y - li.height // 2))
        else:
            for k, txt in enumerate((self.brand_ask, self.brand_promise)):
                fi = self.lyric_img_big(txt)
                im.alpha_composite(fi, ((W - fi.width) // 2,
                                        self.lyric_y - 60 + k * int(self.lyric_size * 1.7)))
        # watermark
        wm = self.lyric_img_small(self.title)
        im.alpha_composite(wm, (36, 36))
        return im

    def lyric_img_big(self, text: str) -> Image.Image:
        key = "B" + text
        if key in self._lyric_cache:
            return self._lyric_cache[key]
        tmp = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
        box = tmp.textbbox((0, 0), text, font=self.font_big, stroke_width=7)
        im = Image.new("RGBA", (box[2] - box[0] + 40, box[3] - box[1] + 40), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((20 - box[0], 20 - box[1]), text, font=self.font_big,
                                fill=(255, 225, 120, 255), stroke_width=7,
                                stroke_fill=(30, 10, 20, 240))
        self._lyric_cache[key] = im
        return im

    def lyric_img_small(self, text: str) -> Image.Image:
        key = "S" + text
        if key in self._lyric_cache:
            return self._lyric_cache[key]
        f = ImageFont.truetype(str(FONT_PATH), 34)
        tmp = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
        box = tmp.textbbox((0, 0), text, font=f, stroke_width=4)
        im = Image.new("RGBA", (box[2] - box[0] + 24, box[3] - box[1] + 24), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((12 - box[0], 12 - box[1]), text, font=f,
                                fill=(255, 255, 255, 210), stroke_width=4,
                                stroke_fill=(20, 10, 30, 200))
        self._lyric_cache[key] = im
        return im


def render(src: Path, out: Path, mode: str, start: float, length: float,
           title: str, brand_ask: str, brand_promise: str, env: dict) -> Path:
    cues = env["cues"]
    scene = Scene(src, mode, cues, start, length, title, brand_ask, brand_promise)
    W, H = scene.W, scene.H
    # The STFT grid is a frame shorter than length*FPS at the tail (the window
    # needs `win` samples), so clamp the frame count to the envelopes we have.
    n = min(int(round(length * FPS)), len(env["bands"]))
    af = f"loudnorm=I=-14:TP=-2.0:LRA=11,alimiter=limit=0.7:level=0,aresample=48000"
    cmd = [_tool("ffmpeg"), "-hide_banner", "-v", "error", "-y",
           "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{W}x{H}", "-r", str(FPS),
           "-i", "-", "-ss", f"{start:.3f}", "-t", f"{length:.3f}", "-i", str(src),
           "-map", "0:v", "-map", "1:a", "-af", af,
           "-c:v", "libx264", "-preset", "medium", "-crf", "20",
           "-pix_fmt", "yuv420p", "-r", str(FPS),
           "-c:a", "aac", "-ar", "48000", "-b:a", "192k",
           "-movflags", "+faststart", str(out)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(n):
        t = i / FPS
        fr = scene.frame(t, env["bands"][i], env["bass"][i], env["vocal"][i],
                         env["punch"][i])
        proc.stdin.write(fr.tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit("ffmpeg failed")
    import clip_standard
    try:
        clip_standard.assert_ok(str(out))
    except SystemExit:
        out.unlink(missing_ok=True)
        raise
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", required=True, type=Path)
    ap.add_argument("--slug", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--mode", choices=("reel", "full"), default="reel")
    ap.add_argument("--out", type=Path)
    ap.add_argument("--seconds", type=float, default=0.0, help="0 = whole track")
    ap.add_argument("--start", type=float, default=0.0)
    args = ap.parse_args()

    sys.path.insert(0, str(MUSIC / "scripts"))
    import branding
    dur = duration(args.src)
    out_dir = Path("/workspace/ax-tools/incoming/reactive")
    out_dir.mkdir(parents=True, exist_ok=True)
    srt = extract_srt(args.src, out_dir / f"{args.slug}.srt")
    cues = parse_srt(srt.read_text(encoding="utf-8"))
    length = args.seconds if args.seconds > 0 else dur
    length = min(length, dur - args.start)
    if args.mode == "reel":
        length = min(length, 88.0)
    out = args.out or out_dir / f"{args.mode}-reactive-{args.slug}.mp4"
    env = analyze(args.src)
    env["cues"] = cues
    render(args.src, out, args.mode, args.start, length, args.title,
           branding.FOLLOW_ASK, branding.FOLLOW_PROMISE, env)
    print(f"{args.mode} reactive -> {out} ({length:.0f}s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
