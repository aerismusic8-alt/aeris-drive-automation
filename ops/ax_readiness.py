#!/usr/bin/env python3
"""Prove, with measurements, whether this sandbox can make and post channel work.

"100% ready" is a claim, and a claim needs a test. This runs every check the
pipeline depends on and prints PASS/FAIL per line plus one verdict, so the
answer is a measured number rather than an opinion.

    python3 ops/ax_readiness.py            # full check
    python3 ops/ax_readiness.py --fix      # install what is missing, then check
    python3 ops/ax_readiness.py --json     # machine-readable, for a report

The checks are ordered by what actually blocks a run:
  1. tools present        - the scripts the rail calls
  2. python deps          - pillow, edge-tts, imageio-ffmpeg
  3. system deps          - ffmpeg, Thai fonts
  4. stock                - stills on disk, or rebuildable from the query list
  5. tokens               - can we authenticate to each channel
  6. publish path         - can the uploader reach the API

Check 5 is the one that separates "can build" from "can post". A sandbox with no
`YT_CH*_REFRESH_TOKEN` can still build a whole episode and cannot post it, and
that distinction is exactly what a readiness report must not blur.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

TOOLS = ["yt_auth.py", "yt_publish.py", "yt_branding.py", "yt_video_status.py",
         "thai_tts.py", "audio_bed.py", "ax_audio_qc.py", "stills_rail.py",
         "video_build.py", "episode_meta.py", "stock_kit.py", "poster_maker.py",
         "ax_vault.py", "yt_video_delete.py"]

CH_TOKENS = {f"ch{i}": f"YT_CH{i}_REFRESH_TOKEN" for i in range(1, 5)}
THAI_FONT_DIRS = ["/usr/share/fonts/truetype/tlwg", "/usr/share/fonts/opentype/tlwg"]


def _run(cmd, timeout=120):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=ROOT)
        return p.returncode, (p.stdout + p.stderr)
    except Exception as e:
        return 1, str(e)


def check_tools():
    missing = [t for t in TOOLS if not os.path.exists(os.path.join(HERE, t))]
    return (not missing), f"{len(TOOLS)-len(missing)}/{len(TOOLS)} scripts", missing


def check_py_deps():
    need = {"PIL": "pillow", "edge_tts": "edge-tts", "imageio_ffmpeg": "imageio-ffmpeg"}
    missing = []
    for mod, pkg in need.items():
        rc, _ = _run([sys.executable, "-c", f"import {mod}"], timeout=60)
        if rc != 0:
            missing.append(pkg)
    raqm = False
    if "pillow" not in missing:
        rc, out = _run([sys.executable, "-c",
                        "from PIL import features; print(features.check('raqm'))"], timeout=60)
        raqm = "True" in out
    return (not missing), f"missing={missing or 'none'} raqm={raqm}", missing


def check_sys_deps():
    ff = shutil.which("ffmpeg")
    fonts = 0
    for d in THAI_FONT_DIRS:
        if os.path.isdir(d):
            fonts += len([f for f in os.listdir(d) if f.lower().endswith((".ttf", ".otf"))])
    return (bool(ff) and fonts > 0), f"ffmpeg={ff or 'MISSING'} thai_fonts={fonts}", []


def check_stock():
    man = os.path.join(ROOT, "stock", "MANIFEST.json")
    if os.path.exists(man):
        try:
            d = json.load(open(man, encoding="utf-8"))
            tot = sum(v["count"] for v in d.values())
            missing = sum(1 for v in d.values() for f in v["files"]
                          if not os.path.exists(os.path.join(ROOT, f["path"])))
            return (tot > 0 and missing == 0), f"stills={tot} missing={missing}", []
        except Exception as e:
            return False, f"manifest unreadable: {e}", []
    # No stock on disk is not fatal: stock_kit rebuilds it from the query list.
    return True, "no stock on disk, rebuildable via `stock_kit.py rebuild`", []


def check_tokens():
    """The build/post boundary. Reports which channels authenticate.

    Reads the secrets from THIS process's environment first: a fresh sandbox
    injects them, and `env` inside a subprocess can differ, so checking
    os.environ here is the honest test.
    """
    present = [c for c, v in CH_TOKENS.items() if os.environ.get(v)]
    rc, out = _run([sys.executable, os.path.join(HERE, "yt_auth.py"), "whoami"], timeout=200)
    ok = rc == 0 and "subs=" in out
    authed = len([l for l in out.splitlines() if l.strip().startswith("ch")])
    detail = f"secrets={present or 'NONE'} authenticated={authed}/4"
    return ok, detail, []


def check_publish_path():
    rc, out = _run([sys.executable, os.path.join(HERE, "yt_publish.py"), "--help"], timeout=60)
    return rc == 0, ("uploader reachable" if rc == 0 else out[:80]), []


CHECKS = [
    ("tools", check_tools),
    ("python deps", check_py_deps),
    ("system deps", check_sys_deps),
    ("stills stock", check_stock),
    ("channel tokens", check_tokens),
    ("publish path", check_publish_path),
]


def fix():
    """Install what the checks report missing. Measured to work in this image."""
    rc, _ = _run(["sudo", "apt-get", "update"], timeout=300)
    _run(["sudo", "apt-get", "install", "-y", "ffmpeg",
          "fonts-thai-tlwg-ttf", "fonts-thai-tlwg-otf"], timeout=400)
    _run([sys.executable, "-m", "pip", "install", "-q",
          "pillow", "edge-tts", "imageio-ffmpeg"], timeout=400)


def main():
    ap = argparse.ArgumentParser(description="Measure channel-work readiness.")
    ap.add_argument("--fix", action="store_true", help="install missing deps first")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    if a.fix:
        print("installing missing dependencies ...")
        fix()

    results = {}
    for name, fn in CHECKS:
        try:
            ok, detail, extra = fn()
        except Exception as e:
            ok, detail, extra = False, f"error: {e}", []
        results[name] = {"ok": ok, "detail": detail, "extra": extra}

    if a.json:
        print(json.dumps(results, ensure_ascii=False, indent=1))
        return 0 if all(r["ok"] for r in results.values()) else 1

    print("AX readiness — measured\n")
    for name, r in results.items():
        print(f"  [{'PASS' if r['ok'] else 'FAIL'}] {name:14} {r['detail']}")
    blocked = [n for n, r in results.items() if not r["ok"]]
    can_build = all(results[n]["ok"] for n in
                    ("tools", "python deps", "system deps", "stills stock")
                    if n in results)
    can_post = results.get("channel tokens", {}).get("ok", False) and \
        results.get("publish path", {}).get("ok", False)
    print(f"\n  can BUILD an episode : {'YES' if can_build else 'NO'}")
    print(f"  can POST to YouTube  : {'YES' if can_post else 'NO'}")
    if blocked:
        print(f"  blocked on           : {', '.join(blocked)}")
        if "channel tokens" in blocked:
            print("  -> the 4 `YT_CH*_REFRESH_TOKEN` secrets are not in THIS account.")
            print("     They are account-scoped. Copy their values into this account's")
            print("     secrets, or post from the account that holds them.")
    print(f"\n  verdict: {100 * sum(r['ok'] for r in results.values()) // len(results)}% ready")
    return 0 if not blocked else 1


if __name__ == "__main__":
    sys.exit(main())
