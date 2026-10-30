# The four repositories

Owner: `github.com/aerismusic8-alt` (K). Each conversation is pinned to one repo
workspace; clone the others when needed:

```bash
git clone --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/aerismusic8-alt/<repo>.git"
```

## aeris-drive-automation — the hub

The AX control plane. Everything else is reached from here.

| Path | Purpose |
|---|---|
| `AKATH_CORE/` | Authority model, task registry (`CANONICAL_TASK_REGISTRY.json`), runtime state |
| `AX_MASTER_BRAIN/` | Durable knowledge + accumulated experience (informs, never commands) |
| `AX_PC_CONTROL/` | PowerShell scripts PC1 runs: Roblox build/publish, local gateway |
| `roblox/` | AX Arena, a Luau game. `src/shared` pure logic, `src/server` + `src/client` glue |
| `scripts/` | Tooling: Luau install/test, PC1 push, GitHub API, Roblox live state, Drive upload |
| `docs/` | Project documentation (incl. `docs/superpowers/plans`) |
| `.agents/skills/` | Project skills, incl. `ax-cloud-desktop` and `ax-account` (this one) |

**Two standing goals live in the registry and must never be closed as ordinary
tasks:** a Roblox game anyone can enter and play, and real revenue from it.

**Roblox specifics** (see the repo's `AGENTS.md` for the full list):
- `roblox/src/shared/` must not call Roblox APIs — that constraint is what makes
  the test suite possible under the plain Luau CLI.
- Standalone Luau 0.743: **no `as` casts** (use `x :: T`) and **no bitwise
  operators** (use `bit32`). Both are parse errors in the CLI.
- Run tests: `cd roblox && ../tools/luau/luau tests/run.luau`.
- Publishing: `AX_PC_CONTROL/pc1-roblox-build.ps1` (Rojo build) +
  `pc1-roblox-publish.ps1` (Open Cloud upload). Studio is only needed to *create*
  a new experience.
- Shipping lag has three causes: stale SHA, wrong build ref (`BUILD_REF` in the
  log is the script's ref, not the code's — the build hard-codes
  `ax-arena-roblox-game`), and the maturity/audience gate. Read the **maturity
  label**, not the playability probe: `multiget-playability-status` answers for
  the *caller* (a logged-out caller gets `GuestProhibited` from every game,
  including Adopt Me).
- The publish workflow must **not** carry `workflow_run` or `push` triggers (the
  `workflow_run` never fires on a non-default branch; `push` races the dispatch).
  The test workflow dispatches the publish with the tested SHA.

## ai-content-lab — Thai story videos

Narrated Thai story videos, ~20 min, from **public-domain Thai literature**, free
tools only. Pushed to `kongkeat938/ai-content-lab` (a second account) and served
from a link.

- `docs/GOAL.md` is the brief (read first). `docs/CONTENT-PLAN.md` = episode slate
  + copyright evidence. `docs/RECIPE.md` = measured technical settings.
- `docs/API.md` = the machine-readable channel an agent pulls episodes from.
- `.agents/skills/thai-story-video/SKILL.md` = how to build one.
- `work/QUEUE.md` = shared backlog; `scripts/claims.py` is the lock between the
  two accounts. **Claim before you build if another account may be working.**
- Two accounts cannot talk to each other — they coordinate through the repo only.

**Non-negotiable rules** (from `docs/AGENTS.md`):
1. Thai sources only — do not adapt a foreign story.
2. Check copyright before writing: Thai copyright is the author's life **+ 50
   years**. Never use a translation (it has its own copyright).
3. Free tools only.
4. Attribute every image (licences in `assets/images/credits.json`).
5. Verify before claiming done (loudness, true peak, colour, timings, seekability).
6. Only the pipeline owner edits `scripts/` — propose, do not edit.
7. Media blobs go to a GitHub Release, never into git.

## autonomous-zero-baht and -1 — the zero-cost content OS

A foundation that researches public RSS, scores topics with transparent rules,
drafts content from templates, validates, and logs decisions. It **does not
promise revenue and does not auto-publish.**

- Workflow: `RESEARCH -> SCORE -> CREATE DRAFTS -> VALIDATE -> LOG DECISIONS`.
- Run: `python -m engine.run` (stdlib only). Outputs under `data/`.
- Config: `config/system.json` (feeds, keywords), `config/limits.json`,
  `config/providers.json` (`paid_providers_allowed: false` everywhere).
- `autonomous-zero-baht` is the fuller/canonical one (has `analytics.py`,
  `publisher.py`, more tests). `-1` is the earlier/parallel variant.
- Principles: no paid APIs/ads/VPS/subscriptions; rule-based fallback; respect
  source terms and rate limits; no fake reviews or engagement; publishing is a
  manual approval stage until platform rules are verified.

## Shared across all four

- Single owner, single authority model (AKATH), single constraint (free only).
- `.openhands/memory/` holds each repo's learned facts; `MEMORY.md` is the index,
  daily logs hold detail. Read them at session start.
- Delivery is the recurring weak point — confirm a real destination before producing.
