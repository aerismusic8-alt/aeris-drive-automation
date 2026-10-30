#!/usr/bin/env python3
"""One command to equip a fresh account/sandbox for channel work.

A new account starts with nothing: no tools on disk, no dependencies, no
stills, no knowledge. Setting that up by hand is a dozen commands and easy to
get subtly wrong. This does the whole thing and then *proves* it worked by
running `ax_readiness.py`, so the result is a measurement, not a promise.

    python3 ops/ax_setup.py                 # full setup from this checkout
    python3 ops/ax_setup.py --bundle FILE   # also import a carried vault bundle
    python3 ops/ax_setup.py --skip-stills   # deps + knowledge only

Steps, in order, each idempotent:
  1. system deps   ffmpeg + Thai fonts (apt, needs sudo)
  2. python deps   pillow, edge-tts, imageio-ffmpeg
  3. knowledge     restore the vault, or import a carried bundle
  4. stills        reuse `stock/` if present, else rebuild from stock_kit
  5. verify        run ax_readiness and print the verdict

What it CANNOT do, on purpose: it never writes a credential. Secrets are
account-scoped and only the account owner can add them, so the script detects
missing tokens, says exactly which names to add and where, and stops there.
It will not print, copy or guess a token value.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PY = sys.executable

CH_TOKENS = {f"ch{i}": f"YT_CH{i}_REFRESH_TOKEN" for i in range(1, 5)}
NEEDED_SECRETS = ["YT_CLIENT_ID", "YT_CLIENT_SECRET"] + list(CH_TOKENS.values())


def step(n, title):
    print(f"\n[{n}] {title}")


def run(cmd, timeout=600, check=False):
    print(f"    $ {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=ROOT)
        if p.stdout.strip():
            print("    " + p.stdout.strip()[:400].replace("\n", "\n    "))
        if p.returncode != 0 and p.stderr.strip():
            print("    ! " + p.stderr.strip()[:300].replace("\n", "\n    "))
        if check and p.returncode != 0:
            raise SystemExit(f"command failed: {cmd}")
        return p.returncode
    except subprocess.TimeoutExpired:
        print("    ! timed out")
        return 1


def sys_deps():
    if shutil.which("ffmpeg") and os.path.isdir("/usr/share/fonts/truetype/tlwg"):
        print("    already present")
        return
    run(["sudo", "apt-get", "update"], timeout=300)
    run(["sudo", "apt-get", "install", "-y", "ffmpeg",
         "fonts-thai-tlwg-ttf", "fonts-thai-tlwg-otf"], timeout=500)


def py_deps():
    run([PY, "-m", "pip", "install", "-q", "--upgrade",
         "pillow", "edge-tts", "imageio-ffmpeg"], timeout=500)


def knowledge(bundle=None):
    if bundle:
        run([PY, os.path.join(HERE, "ax_vault.py"), "import", bundle], timeout=600)
    else:
        run([PY, os.path.join(HERE, "ax_vault.py"), "restore", ROOT], timeout=600)


def stills(skip=False):
    if skip:
        print("    skipped")
        return
    man = os.path.join(ROOT, "stock", "MANIFEST.json")
    if os.path.exists(man):
        rc = run([PY, os.path.join(HERE, "stock_kit.py"), "verify"], timeout=200)
        if rc == 0:
            print("    stock already complete")
            return
    run([PY, os.path.join(HERE, "stock_kit.py"), "rebuild"], timeout=900)


def token_check():
    """Report missing secrets without ever touching their values."""
    missing = [name for name in NEEDED_SECRETS if not os.environ.get(name)]
    if not missing:
        print("    all 6 YouTube secrets are present in this account")
        return True
    print(f"    MISSING in this account: {', '.join(missing)}")
    print("    These are account-scoped. Only the account owner can add them.")
    print("    To enable posting here, copy each value from the account that")
    print("    already holds them (the OpenHands secrets page for that account)")
    print("    into this account's secrets under the SAME names. Do not paste")
    print("    values into a chat, a script, or a file — use the secrets UI.")
    return False


def main():
    ap = argparse.ArgumentParser(description="Equip this sandbox for channel work.")
    ap.add_argument("--bundle", help="portable vault bundle to import")
    ap.add_argument("--skip-stills", action="store_true")
    ap.add_argument("--skip-deps", action="store_true")
    a = ap.parse_args()

    print("AX setup — equipping this sandbox for channel work")
    if not a.skip_deps:
        step(1, "system dependencies (ffmpeg, Thai fonts)")
        sys_deps()
        step(2, "python dependencies")
        py_deps()
    step(3, "knowledge")
    knowledge(a.bundle)
    step(4, "stills stock")
    stills(a.skip_stills)
    step(5, "verify")
    tokens_ok = token_check()
    rc = run([PY, os.path.join(HERE, "ax_readiness.py")], timeout=400)

    print("\n" + "=" * 62)
    if rc == 0 and tokens_ok:
        print("READY — can build and post.")
    elif rc == 0:
        print("READY TO BUILD — but cannot post until the 6 secrets are added.")
        print("That is the one step only the account owner can do.")
    else:
        print("NOT READY — see the FAIL lines above.")
    print("=" * 62)
    return 0 if rc == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
