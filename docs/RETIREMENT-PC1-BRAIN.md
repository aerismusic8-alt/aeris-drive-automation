# Retirement note — the PC1 "Brain" / local-runtime project

Status: RETIRED (2026-11-15, by K). This is the audit trail for the removal; the
project itself is gone from the repo.

## What the project was

The plan was to make PC1 (DESKTOP-RGK6JKB) its own *brain*: a local runtime that
decides and drives execution on the Windows machine around the clock, without an
open ChatGPT session. The canonical loop was

    PC -> Runtime -> Brain -> Control -> Vision/OS/Browser -> Evidence -> Verify -> Write-back

with AX only an occasional executive/upgrade layer, and a MeshCentral transport so
AX could reach the node remotely. It was built as:

- `AKATH_CORE/runtime/` — a Node "AX Runtime": `main.mjs`, `dispatcher.mjs`,
  `node-control.mjs`, `autonomous-planner.mjs`, `pc1-specialist.mjs`,
  `pc1-control.mjs`, `browser-specialist.mjs`, `ai-executor.mjs`,
  recovery planners, canonical sync/writeback, verifier, the Windows
  autostart install/uninstall, and their tests.
- `AX_PC_CONTROL/` — the on-machine workers: `brain1-decision-worker.ps1`,
  `brain1-local-control-worker.ps1`, `brain1-watchdog.ps1`,
  `install-brain1-local-control.ps1`, the `pc1-local-gateway*.ps1` family and
  its contracts, and `pc1-meshcentral-ax-dispatch.ps1`.
- Workflows `ax-pc1-brain1-bootstrap.yml`, `ax-pc1-interactive-foreground.yml`,
  `ax-pc1-system-cleanup-diagnose.yml`.
- The design docs under `AKATH_CORE/` that specified the two-layer
  Runtime/Brain/Control design.

## Why it was retired

K cancelled it (2026-11-15): the node-as-brain design was never the live
direction. The four aeris938-2 revenue jobs (Facebook, TikTok, YouTube
@aerismusicth, Shopee Affiliate) run on GitHub Actions rails and the sandbox, not
on a PC1 brain. The team panel (Duck.ai + Pollinations, two vendors, quorum PASS)
agreed the scope was right and that the one real risk was a shared dependency, so
nothing live was to be touched.

## What remains (untouched)

- The four revenue rails under `music938-1/` / `aeris938-2/` and their workflows.
- The Roblox publish rail (`AX_PC_CONTROL/pc1-roblox-*.ps1` and their workflows).
  Those scripts only *write evidence to* `C:\AX-Runtime\evidence`; they never used
  the runtime code, so they are unaffected.
- `ops/` tooling, the task registry's live growth tasks, and `AX_MASTER_BRAIN/`
  knowledge.

## Machine cleanup — DONE (2026-11-15)

Deleting the repo files does **not** stop anything already scheduled on the
machine, so the cleanup ran on PC1 itself through its self-hosted runner
(`PC1-AERIS`), as a one-off workflow that was deleted after use. Verified
2026-11-15 (run 43732946996):

- **Scheduled tasks: none were present.** All four the project would have
  installed — `AERIS-AKATH-AX-RUNTIME`, `AERIS-PC1-BRAIN1-DECISION`,
  `AERIS-PC1-BRAIN1-LOCAL-CONTROL`, `AERIS-PC1-BRAIN1-WATCHDOG` — were already
  absent, and no other `AERIS-*` / `*BRAIN1*` / `*AX-RUNTIME*` /
  `*MESHCENTRAL*` task exists. The runtime was never actually installed, so the
  "live scheduled task" risk was theoretical.
- **Payload removed:** `C:\AX-Bootstrap\brain1` (4 files) and the files
  `brain1-decision-worker.ps1`, `brain1-local-control-worker.ps1`,
  `brain1-watchdog.ps1`, `brain1-install-proof.json` under `C:\AX-Runtime`.
  The Node entrypoints (`main.mjs`, `dispatcher.mjs`, `node-control.mjs`) were
  never deployed there.
- `C:\AX-Runtime\evidence` was **kept** — the Roblox scripts still write there.
- Proof: `C:\AX-Runtime\evidence\pc1-brain-cleanup-proof.json`.

`C:\AX-Runtime` is a large general scratch directory (~8,600 files: media,
probes, unrelated scripts), so only the named payload was removed — never the
whole directory.

## Recovery

Every removed file's blob SHA is listed in the commit message body and in the
session log. Restore any of them with `git show <sha> > <path>`, or revert the
purge commit.
