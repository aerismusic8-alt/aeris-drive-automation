#!/usr/bin/env python3
"""The briefing a cold session reads instead of remembering.

Every conversation starts with no history and the injected memory card is capped
at 6 KB, so "the agent forgot" is a property of the setup, not of the model — and
a bigger model is not the answer here (Rule #1: free only). The fix is to stop
asking the model to remember anything: this briefing derives the live state from
the artifacts themselves (the hold marker, git, the release, the vault), so any
model on any pod starts with the truth instead of a recollection.

    python3 ops/brief.py          # one screen
    python3 ops/brief.py --full   # plus the per-lane catalogue table

Anything that cannot be read is printed as `unknown`, never guessed — a blank
row is data, and a guess is how a session decides on stale facts.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MUSIC = ROOT / "music938-1"


def run(*cmd: str, cwd: Path = ROOT, timeout: int = 90) -> tuple[bool, str]:
    try:
        p = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True,
                           timeout=timeout)
        return p.returncode == 0, (p.stdout or p.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, f"unknown ({exc.__class__.__name__})"


def git_state() -> list[str]:
    _, branch = run("git", "rev-parse", "--abbrev-ref", "HEAD")
    _, dirty = run("git", "status", "--porcelain")
    _, ahead = run("git", "rev-list", "--count", "origin/HEAD..HEAD")
    out = [f"repo        : {ROOT.name}  branch={branch or 'unknown'}"]
    n = len([ln for ln in dirty.splitlines() if ln.strip()])
    out.append(f"working tree: {n} uncommitted file(s)" if n else
               "working tree: clean")
    if ahead.strip().isdigit():
        out.append(f"unpushed    : {ahead.strip()} commit(s) ahead of origin")
    return out


def hold_state() -> str:
    sys.path.insert(0, str(ROOT / "ops"))
    try:
        import hold_gate
    except Exception as exc:
        return f"unknown ({exc.__class__.__name__})"
    if not hold_gate.active():
        return "lifted — publishing is allowed"
    return f"ACTIVE — {hold_gate.reason()}"


def catalogue(full: bool) -> list[str]:
    ok, out = run(sys.executable, "scripts/genres.py", "--report",
                  cwd=MUSIC, timeout=120)
    if not ok:
        return [f"unknown ({out.splitlines()[0] if out else 'no output'})"]
    lines = out.splitlines()
    keep = [ln for ln in lines if ln.startswith(("masters:", "  TOTAL",
                                                 "off-direction"))]
    if full:
        keep = [ln for ln in lines if ln.strip()]
    else:
        keep += [ln for ln in lines if ln.strip().startswith(("rock", "pop",
                                                              "edm", "hiphop",
                                                              "alternative"))]
    return keep


def vault_state() -> str:
    ok, out = run(sys.executable, "ops/login_vault.py", "status", timeout=60)
    if not ok:
        return f"unknown ({out.splitlines()[0] if out else 'no output'})"
    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    return "; ".join(lines[:2]) if lines else "nothing saved"


def compass_state() -> str:
    ok, out = run(sys.executable, "ops/compass.py", "--check", timeout=120)
    return out.splitlines()[-1].strip() if ok and out else f"unknown ({out[:60]})"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--full", action="store_true",
                    help="print the whole catalogue table")
    a = ap.parse_args(argv)

    print("== brief (derived from artifacts, not memory) ==")
    for line in git_state():
        print(line)
    print(f"publish hold: {hold_state()}")
    print(f"compass     : {compass_state()}")
    print(f"login vault : {vault_state()}")
    print("catalogue   :")
    for line in catalogue(a.full):
        print(f"  {line}")
    print("\nA live browser session is NOT checked here (it costs a browser "
          "launch);\nrun check_login.py when the next step needs Flow or Gemini.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
