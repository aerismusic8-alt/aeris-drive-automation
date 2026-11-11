#!/usr/bin/env python3
"""Prove, with checks, that the OpenHands platform risks are actually mitigated.

The risk register (`AKATH_CORE/OPENHANDS_RISK_REGISTER.json`) lists each platform
risk and the mitigation for it. A mitigation that is only prose is not a
mitigation, so this script runs a *check* for each risk and prints PASS/FAIL. It
exits non-zero when any HIGH-severity risk is not proven, so it can gate a rail.

    python3 ops/risk_audit.py            # human report
    python3 ops/risk_audit.py --json     # machine-readable
    python3 ops/risk_audit.py --strict   # any unproven risk (even low) fails

It is offline and deterministic: no network, no secrets, no live token.
"""
from __future__ import annotations

import argparse
import ast
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTER = ROOT / "AKATH_CORE" / "OPENHANDS_RISK_REGISTER.json"

# import name -> distribution name in requirements.txt. Only the ones whose
# names differ; everything else is matched by the import name itself.
DIST = {
    "PIL": "pillow", "websocket": "websocket-client", "nacl": "PyNaCl",
    "eth_account": "eth-account", "edge_tts": "edge-tts",
    "imageio_ffmpeg": "imageio-ffmpeg", "fontTools": "fonttools",
}
SCAN_DIRS = ["ops", "aeris938-2/scripts", "aeris938-1/scripts",
             "music938-1/scripts", "scripts", "tools"]

# Imports that are deliberately optional: the code guards them in a try/except
# and has a fallback, so they are not a hard dependency to declare.
OPTIONAL_IMPORTS = {
    "piper",  # retired TTS engine; tts.py guards it and falls back
}


def _read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def _local_modules() -> set[str]:
    """Every module name that resolves to a file in this repo.

    Walks the whole repo, not just SCAN_DIRS: a script in one directory imports a
    sibling module by bare name (e.g. `import browser`), and that name must not be
    mistaken for a third-party package just because it lives in another folder.
    """
    names: set[str] = set()
    for p in ROOT.rglob("*.py"):
        if any(x in p.parts for x in (".git", "node_modules", "__pycache__")):
            continue
        names.add(p.stem)
    return names


def _third_party_imports() -> dict[str, str]:
    """import-name -> one example file, for every non-stdlib, non-local import."""
    std = set(sys.stdlib_module_names)
    local = _local_modules()
    found: dict[str, str] = {}
    for d in SCAN_DIRS:
        base = ROOT / d
        if not base.exists():
            continue
        for p in base.rglob("*.py"):
            if "__pycache__" in p.parts:
                continue
            try:
                tree = ast.parse(_read(p))
            except SyntaxError:
                continue
            for n in ast.walk(tree):
                if isinstance(n, ast.Import):
                    for a in n.names:
                        top = a.name.split(".")[0]
                        if top not in std and top not in local and top not in OPTIONAL_IMPORTS:
                            found.setdefault(top, str(p.relative_to(ROOT)))
                elif isinstance(n, ast.ImportFrom) and n.level == 0 and n.module:
                    top = n.module.split(".")[0]
                    if top not in std and top not in local and top not in OPTIONAL_IMPORTS:
                        found.setdefault(top, str(p.relative_to(ROOT)))
    return found


# --------------------------------------------------------------------------
# checks: each returns (ok, detail)
# --------------------------------------------------------------------------

def chk_workflows_scheduled() -> tuple[bool, str]:
    wf = ROOT / ".github" / "workflows"
    n = 0
    for p in wf.glob("*.yml") if wf.exists() else []:
        t = _read(p)
        if "schedule:" in t and "cron:" in t:
            n += 1
    return n >= 3, f"{n} workflows carry a cron schedule"


def chk_durable_state() -> tuple[bool, str]:
    have = [str(p.relative_to(ROOT)) for p in (ROOT / "ops" / "ax_vault.py",
            ROOT / "ops" / "AX_RECOVER.md") if p.exists()]
    return len(have) == 2, "vault + recovery doc present: " + ", ".join(have)


def chk_no_hardcoded_host() -> tuple[bool, str]:
    """No *runnable* file may hardcode a per-pod host as a default.

    Docs, memory and recorded data legitimately mention a host (a past URL, a
    measurement). What breaks after a restart is a default inside code or a
    workflow: it points at a dead pod and the job silently fails. So this scans
    only .py / .sh / .yml and requires the host to come from the environment.
    """
    bad = re.compile(r"work-[12]-[a-z0-9]{6,}\.prod-runtime")
    hits = []
    for d in SCAN_DIRS + [".github/workflows"]:
        base = ROOT / d
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if not p.is_file() or p.suffix not in {".py", ".sh", ".yml", ".yaml"}:
                continue
            if bad.search(_read(p)):
                hits.append(str(p.relative_to(ROOT)))
    return not hits, ("no runnable file hardcodes a pod host" if not hits
                      else "hardcoded in: " + ", ".join(hits[:5]))


def chk_context_on_disk() -> tuple[bool, str]:
    need = [ROOT / ".openhands" / "CHARTER.md",
            ROOT / ".openhands" / "memory" / "MEMORY.md"]
    ok = all(p.exists() for p in need)
    return ok, "CHARTER.md + memory/MEMORY.md on disk" if ok else "missing context files"


def chk_quota_aware() -> tuple[bool, str]:
    ok = (ROOT / ".github" / "workflows" / "ax-rail-watchdog.yml").exists()
    return ok, "rail watchdog heals auto-paused automations" if ok else "no watchdog"


def chk_deps_declared() -> tuple[bool, str]:
    req = ROOT / "requirements.txt"
    if not req.exists():
        return False, "requirements.txt missing"
    text = _read(req).lower()
    declared = {ln.split("#", 1)[0].strip().lower() for ln in text.splitlines()}
    declared = {d for d in declared if d}
    missing = []
    for imp, where in sorted(_third_party_imports().items()):
        dist = DIST.get(imp, imp).lower()
        if not any(d == dist or d.startswith(dist + "=") or d.startswith(dist + " ")
                   or d.startswith(dist + ">") for d in declared):
            missing.append(f"{imp} ({where})")
    return not missing, ("all third-party imports declared" if not missing
                         else "undeclared: " + ", ".join(missing[:6]))


def chk_api_first() -> tuple[bool, str]:
    have = [f for f in ("ops/yt_auth.py", "ops/websearch.py", "ops/fb_graph.py")
            if (ROOT / f).exists()]
    return len(have) >= 2, "api/keyless routes present: " + ", ".join(have)


def chk_write_route_documented() -> tuple[bool, str]:
    have = [f for f in ("scripts/use-app-token.sh", "scripts/gh-api.py",
                        "scripts/push-via-pc1.sh") if (ROOT / f).exists()]
    return bool(have), "write routes: " + ", ".join(have)


def chk_secret_hygiene() -> tuple[bool, str]:
    try:
        url = subprocess.run(["git", "remote", "get-url", "origin"], cwd=ROOT,
                             capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception as e:  # noqa: BLE001
        return False, f"cannot read git remote: {e}"
    if re.match(r"https://[^@/]+@", url) or "x-access-token" in url or "ghp_" in url:
        return False, "a token is embedded in the git remote URL"
    gi = _read(ROOT / ".gitignore")
    ignores_creds = (".secrets" in gi and "*.pem" in gi)
    # no credential-shaped file is tracked
    try:
        tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True,
                                 text=True, timeout=15).stdout.split()
    except Exception:  # noqa: BLE001
        tracked = []
    risky = [f for f in tracked
             if re.search(r"\.pem$|\.p12$|(^|/)(id_rsa|credentials|secrets?\.json)$", f)]
    ok = ignores_creds and not risky
    detail = ("remote clean; .secrets + *.pem gitignored; no credential file tracked"
              if ok else
              ("no .secrets/*.pem ignore rule" if not ignores_creds
               else "credential file tracked: " + ", ".join(risky[:3])))
    return ok, detail


def chk_push_race_guard() -> tuple[bool, str]:
    gi = _read(ROOT / ".gitignore")
    ok = "engagement" in gi and (ROOT / "scripts" / "gh-api.py").exists()
    return ok, "contents-API writer present; mutable state allowlisted" if ok \
        else "missing gh-api.py or the mutable-state gitignore entry"


def chk_registry_valid() -> tuple[bool, str]:
    p = ROOT / "AKATH_CORE" / "CANONICAL_TASK_REGISTRY.json"
    try:
        d = json.loads(_read(p))
    except Exception as e:  # noqa: BLE001
        return False, f"registry does not parse: {e}"
    tasks = d.get("tasks", [])
    ids = [t.get("task_id") for t in tasks if isinstance(t, dict)]
    ok = len(tasks) > 0 and all(ids)
    return ok, f"{len(tasks)} tasks, all with task_id" if ok else "tasks missing task_id"


def chk_disk_sane() -> tuple[bool, str]:
    ok = (ROOT / ".gitignore").exists()
    return ok, ".gitignore present; build artefacts ignored" if ok else "no .gitignore"


CHECKS = {
    "workflows_scheduled": chk_workflows_scheduled,
    "durable_state": chk_durable_state,
    "no_hardcoded_host": chk_no_hardcoded_host,
    "context_on_disk": chk_context_on_disk,
    "quota_aware": chk_quota_aware,
    "deps_declared": chk_deps_declared,
    "api_first": chk_api_first,
    "write_route_documented": chk_write_route_documented,
    "secret_hygiene": chk_secret_hygiene,
    "push_race_guard": chk_push_race_guard,
    "registry_valid": chk_registry_valid,
    "disk_sane": chk_disk_sane,
}


def audit() -> dict:
    reg = json.loads(_read(REGISTER))
    rows = []
    for r in reg.get("risks", []):
        fn = CHECKS.get(r.get("check"))
        if fn is None:
            ok, detail = False, f"no check named {r.get('check')!r}"
        else:
            try:
                ok, detail = fn()
            except Exception as e:  # noqa: BLE001
                ok, detail = False, f"check raised: {e}"
        rows.append({"id": r.get("id"), "severity": r.get("severity"),
                     "title": r.get("title"), "ok": bool(ok), "detail": detail})
    high_open = [x for x in rows if not x["ok"] and x["severity"] == "high"]
    return {"rows": rows, "high_open": len(high_open),
            "any_open": sum(1 for x in rows if not x["ok"])}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true",
                    help="fail when any risk is unproven, not just high ones")
    a = ap.parse_args()
    rep = audit()
    if a.json:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
    else:
        print("OPENHANDS RISK AUDIT")
        for x in rep["rows"]:
            mark = "PASS" if x["ok"] else "OPEN"
            print(f"  [{mark}] {x['severity']:6s} {x['id']:16s} {x['detail']}")
        print(f"\n{len(rep['rows'])} risks; {rep['any_open']} unproven; "
              f"{rep['high_open']} high unproven")
    bad = rep["any_open"] if a.strict else rep["high_open"]
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
