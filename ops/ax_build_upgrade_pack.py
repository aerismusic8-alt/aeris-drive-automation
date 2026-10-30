#!/usr/bin/env python3
"""Build the portable AX AI-upgrade pack: skills + rails + memory, one tarball.

The deliverable of this project is the AGENT, not a hand-built channel. This
script produces the thing that upgrades an agent: every skill, rail, script and
lesson learned, in one archive that can be carried to another OpenHands account
and unpacked with a single command.

    python3 ops/ax_build_upgrade_pack.py            # -> out/ax-ai-upgrade-<date>.tar.gz
    python3 ops/ax_build_upgrade_pack.py --out DIR

What goes in, and why each part matters:

  skills/   the two skills (`youtube-channel-builder`, `ax-pc1-ops`) - the
            procedural knowledge, with the scripts they invoke
  ops/      the rails: episode driver, audio/video builders, publishing, the
            PC1 fix, the vault tool, the readiness check
  memory/   MEMORY.md + the daily logs - the curated index and the raw detail
  bundle/   a portable copy of the knowledge vault (tar.gz + manifest), so an
            account that cannot read our KV store still gets everything
  docs/     the Thai guides and the prompt to hand to the receiving agent

Deliberately NOT included: any credential. The builder refuses a file whose name
or bytes look like a token, the same rule `ax_vault.py` enforces, so this archive
is safe to hand over by any channel.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# Credential guards. The same shapes ax_vault.py refuses.
BAD_NAME = re.compile(r"token|secret|credential|password|passwd|apikey|\.pem$|\.key$", re.I)
BAD_BYTES = re.compile(
    rb"(AIza[0-9A-Za-z\-_]{30,}"          # Google API key
    rb"|gh[pousr]_[A-Za-z0-9]{30,}"       # GitHub token
    rb"|sk-[A-Za-z0-9]{32,}"              # OpenAI-style
    rb"|1//[0-9A-Za-z\-_]{30,}"           # Google refresh token
    rb"|ya29\.[0-9A-Za-z\-_]{20,})"       # Google access token
)

# (source path relative to ROOT, destination path inside the pack)
SKILLS = [
    ".agents/skills/youtube-channel-builder",
    ".agents/skills/ax-pc1-ops",
]

OPS_FILES = [
    "ax_make_episode.py", "ax_channels.py", "ax_channels.json", "ax_setup.py",
    "ax_readiness.py", "ax_vault.py", "stock_kit.py", "stills_rail.py",
    "thai_tts.py", "audio_bed.py", "video_build.py", "episode_meta.py",
    "poster_maker.py", "yt_auth.py", "yt_publish.py", "yt_branding.py",
    "yt_video_status.py", "yt_video_delete.py", "channel_branding.json",
    "pc1_fix_remote.ps1", "check_pc1.py", "pc1_live.py", "pc1_desktop.py",
    "pc1mcp.py", "pc1_uia.py", "pc1_serve_fix.sh", "ax_build_upgrade_pack.py",
]

DOCS = [
    "AX_CHANNELS.md", "AX_CHANNEL_DOSSIERS.md", "AX_RECOVER.md",
    "AX_MIGRATION.md", "HOW_TO_POST_FROM_AN_AGENT.md",
    "PROMPT_FOR_KONGKEAT_AGENT.md", "PC1-FIX-TH.md", "HOLD.md",
]

MEMORY = [".openhands/memory/MEMORY.md", ".openhands/memory/2026-10-26.md",
          ".openhands/memory/2026-10-24.md"]


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def looks_like_credential(name: str, data: bytes) -> str | None:
    if BAD_NAME.search(os.path.basename(name)):
        return f"name matches a credential pattern: {os.path.basename(name)}"
    if BAD_BYTES.search(data):
        return f"bytes match a token shape: {name}"
    return None


def collect_file(rel: str, files: dict[str, bytes], refused: list[str]) -> None:
    """Add one file if it exists and carries no credential."""
    src = ROOT / rel
    if not src.is_file():
        refused.append(f"MISSING {rel}")
        return
    data = src.read_bytes()
    why = looks_like_credential(rel, data)
    if why:
        refused.append(f"REFUSED {rel} ({why})")
        return
    files[rel] = data


def collect_tree(rel_dir: str, files: dict[str, bytes], refused: list[str],
                 dest_prefix: str | None = None) -> None:
    base = ROOT / rel_dir
    if not base.is_dir():
        refused.append(f"MISSING DIR {rel_dir}")
        return
    for p in sorted(base.rglob("*")):
        if not p.is_file():
            continue
        if "__pycache__" in p.parts or p.suffix in (".pyc", ".log"):
            continue
        rel = str(p.relative_to(ROOT))
        why = looks_like_credential(rel, p.read_bytes())
        if why:
            refused.append(f"REFUSED {rel} ({why})")
            continue
        dest = rel
        if dest_prefix:
            dest = dest_prefix + "/" + str(p.relative_to(base))
        files[dest] = p.read_bytes()


def build_vault_bundle(files: dict[str, bytes], refused: list[str]) -> None:
    """A portable copy of the knowledge vault, so an account that cannot read
    our KV store still receives the whole set in one file."""
    out = ROOT / "out" / "_bundle"
    out.mkdir(parents=True, exist_ok=True)
    tgz = out / "knowledge.tar.gz"
    cmd = [sys.executable, str(ROOT / "ops" / "ax_vault.py"), "export", str(tgz)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            refused.append(f"VAULT EXPORT FAILED: {r.stderr.strip()[:200]}")
            return
        data = tgz.read_bytes()
        why = looks_like_credential("knowledge.tar.gz", data)
        if why:
            refused.append(f"REFUSED vault bundle ({why})")
            return
        files["bundle/knowledge.tar.gz"] = data
        man = Path(str(tgz) + ".manifest.json")
        if man.exists():
            # The exported manifest records the absolute build path, which is
            # meaningless on the receiving side. Rewrite it to the command that
            # works from the unpacked pack.
            m = json.loads(man.read_text(encoding="utf-8"))
            m["restore_command"] = "python3 ops/ax_vault.py import bundle/knowledge.tar.gz"
            files["bundle/knowledge.tar.gz.manifest.json"] = json.dumps(
                m, ensure_ascii=False, indent=2).encode("utf-8")
    except Exception as e:  # never fail the whole pack over the bundle
        refused.append(f"VAULT EXPORT ERROR: {e}")


def validate_skill(text: str, name: str) -> list[str]:
    """Minimal frontmatter check, so a broken skill cannot ship silently."""
    errs = []
    if not text.startswith("---\n"):
        errs.append(f"{name}: missing frontmatter")
        return errs
    end = text.find("\n---\n", 4)
    if end < 0:
        errs.append(f"{name}: frontmatter not closed")
        return errs
    fm = text[4:end]
    if not re.search(r"^name:\s*\S", fm, re.M):
        errs.append(f"{name}: no name: field")
    if not re.search(r"^description:\s*\S", fm, re.M):
        errs.append(f"{name}: no description: field")
    return errs


def write_install_docs(files: dict[str, bytes], stamp: str) -> None:
    files["README.md"] = README_TXT.encode("utf-8")
    files["INSTALL.md"] = INSTALL_TXT.encode("utf-8")
    files["PROMPT_FOR_NEW_AGENT.md"] = PROMPT_TXT.encode("utf-8")
    files["PACK_INFO.json"] = json.dumps(
        {"name": "AX AI upgrade pack", "built_utc": stamp, "schema": 1,
         "contains_credentials": False}, indent=2).encode("utf-8")


README_TXT = """# AX AI upgrade pack

Everything learned building the 4 Thai YouTube channels and driving PC1, packed
so it can be handed to another OpenHands agent in one step.

**No credentials are in this pack.** Tokens live in OpenHands secrets, which are
account-scoped and must be re-created on the receiving account. See INSTALL.md.

## What is inside

| path | what it is |
|---|---|
| `skills/youtube-channel-builder/` | build and publish an episode: narration-first audio, music bed ducking, stills, 1080p assembly, metadata, upload. Plus `scripts/` with the working rails and `TOOLS.md`, a task-to-command index. |
| `skills/ax-pc1-ops/` | operate and repair PC1: the winremote MCP tool tiers (why `Shell`/`FileWrite`/`PlaySound` are missing by default), the tailnet route, and how to read the self-hosted runner. |
| `ops/` | the rails as standalone scripts, including `pc1_fix_remote.ps1` (the PC1 repair), `check_pc1.py`, `ax_make_episode.py` (one-command episode), and `ax_vault.py`. |
| `memory/` | `MEMORY.md` - the curated index of what was learned - plus the daily logs with the raw detail. |
| `docs/` | the Thai guides: channel summary, dossiers, recovery, migration, and the PC1 fix. |
| `bundle/` | a portable copy of the knowledge vault (`knowledge.tar.gz` + manifest). |

## Install, in one step

```bash
tar -xzf ax-ai-upgrade-*.tar.gz
cd ax-ai-upgrade-*
python3 ops/ax_setup.py --bundle bundle/knowledge.tar.gz
```

Then paste `PROMPT_FOR_NEW_AGENT.md` as the first message of a new conversation.
Full detail, including the secrets to re-create, is in `INSTALL.md`.

## The one rule that governs the content

Retention is won by the **sound**. The narration is the product; pictures support
it. Build and measure the audio bed first, then lay stills on top. The music bed
must never be louder than the voice, even during pauses.
"""

INSTALL_TXT = """# Install this pack

## 1. Unpack

```bash
tar -xzf ax-ai-upgrade-*.tar.gz
cd ax-ai-upgrade-*
```

## 2. Install dependencies and restore the knowledge

One command installs system deps (ffmpeg + Thai fonts), the Python deps
(pillow, edge-tts, imageio-ffmpeg), imports the carried knowledge bundle, and
finishes by running a readiness check that measures everything:

```bash
python3 ops/ax_setup.py --bundle bundle/knowledge.tar.gz
```

If the repo already holds the knowledge set, `python3 ops/ax_setup.py` is enough.

Check status at any time:

```bash
python3 ops/ax_readiness.py          # PASS/FAIL on every dependency, with a %
python3 ops/ax_readiness.py --fix    # install what is missing, then measure
```

## 3. Re-create the secrets (the step the pack cannot do for you)

The pack carries no credentials. On the receiving account, add these in
OpenHands -> Settings -> Secrets:

| secret | what it is |
|---|---|
| `YT_CLIENT_ID`, `YT_CLIENT_SECRET` | the Google OAuth app |
| `YT_REFRESH_TOKEN` (ch1), `YT_CH2_REFRESH_TOKEN`, `YT_CH3_REFRESH_TOKEN`, `YT_CH4_REFRESH_TOKEN` | one per channel |
| `OPENHANDS_API_KEY` | to reach the automation API and the KV vault |
| `PC1_MCP_TOKEN_2` | the key for the PC1 winremote MCP server |

Confirm the YouTube side before doing anything else:

```bash
python3 ops/yt_auth.py whoami --all     # all 4 channels must authenticate
```

If a token fails, stop and report. **Do not rotate accounts** - that is forbidden.

## 4. Skills

The skills in `skills/` are the procedural knowledge. Install them into the
agent's workspace so it can load them:

```bash
mkdir -p .agents/skills
cp -r skills/* .agents/skills/
```

Each skill's `SKILL.md` has frontmatter with `name` and `description`; the agent
loads a skill when its description matches the task.

## 5. The vault, and why there are two copies

The AX knowledge vault lives in the OpenHands automation KV store, which is
**account-scoped** - it cannot follow you to another account. That is why the
pack carries `bundle/knowledge.tar.gz`: a portable copy. After importing it, the
receiving account has its own vault and can keep it current:

```bash
python3 ops/ax_vault.py pack       # copy the knowledge set into this account's vault
python3 ops/ax_vault.py bootstrap  # refresh the self-recovery keys
python3 ops/ax_vault.py verify     # confirm the local tree matches the vault
```

Recovery after a sandbox dies is documented in `docs/AX_RECOVER.md`.
"""

PROMPT_TXT = """# First message for the receiving agent

Copy everything below into a new OpenHands conversation, after unpacking the pack
and running `python3 ops/ax_setup.py --bundle bundle/knowledge.tar.gz`.

---

You are the AX agent. The deliverable is **you**, not a hand-built channel:
K's goal is an AI agent that runs 4 Thai YouTube channels on free cloud tools and
a 0 THB budget. **Never rotate accounts.**

**Read before acting, in this order:**

1. `memory/MEMORY.md` - the curated index of everything learned. It points at the
   daily logs for detail.
2. `skills/youtube-channel-builder/SKILL.md` and `TOOLS.md` - how to build an
   episode, and the task-to-command index.
3. `skills/ax-pc1-ops/SKILL.md` - if PC1 is involved.
4. `docs/AX_CHANNELS.md` - the 4-channel table, then `AX_CHANNEL_DOSSIERS.md`.

**The rule that governs everything: AUDIO FIRST.** Retention is won by the sound.
The narration is the product; pictures are support. Build and measure the audio
bed first, then lay stills on top. The music bed must never be louder than the
voice, even during pauses. Targets: **-17 LUFS, true peak <= -1 dBFS**, no
silence over 1.2 s.

**Hard rules**

1. Never claim to have watched or heard anything. Report measured numbers only.
2. **AX does not upload.** K reviews first; publish only when K says so.
3. Never assume a duration. Measure it, then add or cut a story.
4. Never rename a channel or change its direction without K's explicit approval.
5. Long episodes are >= 10 minutes.

**Verify with a real call, never with a port.** A `/health` 200 proves a process
is up, not that it can act. Finish every check with a real tool call.

**Where the knowledge lives.** A sandbox is disposable. Anything only on disk is
already lost. Keep the knowledge set in the vault (`python3 ops/ax_vault.py
pack`) and read `docs/AX_RECOVER.md` if the workspace looks empty.

Start by running `python3 ops/ax_readiness.py` and reporting the result, then ask
K which channel to work on.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description="Build the portable AX AI upgrade pack.")
    ap.add_argument("--out", default=None, help="output directory (default out/)")
    ap.add_argument("--no-bundle", action="store_true", help="skip the vault bundle")
    a = ap.parse_args()

    stamp = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%d")
    out_dir = Path(a.out) if a.out else ROOT / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    pkg = f"ax-ai-upgrade-{stamp}"

    files: dict[str, bytes] = {}
    refused: list[str] = []

    for skill in SKILLS:
        # Keep the skill's own directory name, or the two SKILL.md files collide.
        collect_tree(skill, files, refused, dest_prefix=f"skills/{Path(skill).name}")

    for name in OPS_FILES:
        collect_file(f"ops/{name}", files, refused)

    for name in DOCS:
        src = ROOT / "ops" / name
        if src.is_file():
            data = src.read_bytes()
            why = looks_like_credential(name, data)
            if why:
                refused.append(f"REFUSED ops/{name} ({why})")
            else:
                files[f"docs/{name}"] = data
        else:
            refused.append(f"MISSING ops/{name}")

    for rel in MEMORY:
        src = ROOT / rel
        if src.is_file():
            files[f"memory/{src.name}"] = src.read_bytes()
        else:
            refused.append(f"MISSING {rel}")

    if not a.no_bundle:
        build_vault_bundle(files, refused)

    write_install_docs(files, stamp)

    # Validate the skills before shipping them.
    errs: list[str] = []
    for dest in list(files):
        if dest.endswith("SKILL.md"):
            errs += validate_skill(files[dest].decode("utf-8", "replace"), dest)
    if errs:
        print("SKILL VALIDATION FAILED:")
        for e in errs:
            print("  " + e)
        return 2

    # Build the archive deterministically (fixed mtime, sorted, no owner info).
    manifest = []
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for dest in sorted(files):
            data = files[dest]
            info = tarfile.TarInfo(f"{pkg}/{dest}")
            info.size = len(data)
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            tf.addfile(info, io.BytesIO(data))
            manifest.append({"path": dest, "bytes": len(data), "sha256": sha256(data)})

    blob = buf.getvalue()
    archive = out_dir / f"{pkg}.tar.gz"
    archive.write_bytes(blob)
    man = {
        "name": pkg,
        "built_utc": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "archive": archive.name,
        "archive_bytes": len(blob),
        "archive_sha256": sha256(blob),
        "file_count": len(manifest),
        "contains_credentials": False,
        "files": manifest,
    }
    (out_dir / f"{pkg}.tar.gz.manifest.json").write_text(
        json.dumps(man, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"built {archive}")
    print(f"  files    : {len(manifest)}")
    print(f"  bytes    : {len(blob):,}")
    print(f"  sha256   : {man['archive_sha256'][:16]}")
    if refused:
        print(f"  skipped  : {len(refused)}")
        for r in refused:
            print("    " + r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
