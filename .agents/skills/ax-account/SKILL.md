---
name: ax-account
description: The account playbook for K's aeris938 / AKATH workspace (GitHub user aerismusic8-alt). Consolidates every repository in the account — aeris-drive-automation (AX Roblox + PC1 control), ai-content-lab (Thai story videos), autonomous-zero-baht / -1 (zero-cost content OS) — into one set of standing rules, project maps, environment facts and delivery routes. Load this at the start of any session in this workspace, when the task mentions AKATH, AX, K, PC1, Roblox, Thai story video, music938, karaoke, Google Drive upload, or "free only", or when you are unsure which repository or convention applies.
triggers:
  - akath
  - ax account
  - ax-account
  - aeris938
  - aerismusic8
  - aeris-drive-automation
  - ai-content-lab
  - autonomous-zero-baht
  - zero-baht
  - music938
  - thai story
  - karaoke
  - pc1
  - roblox
  - กฎถาวร
  - ฟรีเท่านั้น
  - free only
---

# AX account playbook

One skill for the whole account. The repositories below share a single owner (K),
a single authority model (AKATH), and a single hard constraint (free only). Read
this before you plan, so a fresh session does not re-derive rules that already
exist on disk.

Detail lives in `references/` — open only the file you need:

| File | When to read it |
|---|---|
| `references/projects.md` | before touching any of the four repositories |
| `references/conventions.md` | before writing code, docs or media in any of them |
| `references/environment.md` | before running tools, pushing, or reaching for a browser |
| `scripts/install-agent-skills.sh` | after a pod recycle, to restore this skill for every conversation |

## 1. Identity and authority

- **K is the final authority.** K sets direction, approves plans, and is the only
  one who signs in to accounts. When K says stop, stop and record why.
- **AKATH** is the organisation; **AX** is the executive/orchestration system; the
  **Master Brain** is durable knowledge only — it may inform design but must never
  create current tasks or current operational state.
- Completion gate: a job is DONE only when (1) execution produced a real result,
  (2) evidence is persisted and linked to the same job identity, and (3) verification
  passes. A claim of "done" without evidence is not done.
- A deadline is never silently extended; a missed one triggers cause analysis.

## 2. Rule #1 — free only (hard gate)

> "อันดับแรกต้องฟรี ถ้ามีการจ่ายเงิน ไม่ต้องคุยต่ออีกยกเลิกไปเลย"

**If an option costs money, cancel it immediately — do not propose it, do not
compare prices.** No paid API, no subscription, no credits, no "it's cheap".
Allowed: anything free — `edge-tts`, `ffmpeg`, Luau, GitHub, OpenHands, and
login-only web apps driven through the cloud desktop (Flow Music, Gemini web).

Never propose the OpenAI/ChatGPT API again. K ruled it out.

Two consequences that decide real work:

- **Do not pay Roblox.** The 1,000-Robux Kids-and-Select publishing fee is ruled
  out; the free road to a public game is the 250-engaged-player review.
- **Free-only collides with some deliverables.** A listenable sung vocal is *not*
  reachable from free TTS plus an offline synth. When the deliverable needs a
  capability that free tools do not have, say so up front — do not build a
  substitute engine and produce a large artifact that must be thrown away.

## 3. The four repositories

Full maps in `references/projects.md`. One line each:

| Repo | What it is |
|---|---|
| `aeris-drive-automation` | AX control plane: Roblox game (Luau), PC1 Windows automation, task registry, delivery scripts. The hub. |
| `ai-content-lab` | Thai narrated story videos (~20 min), public-domain Thai literature, free tools, YouTube publishing. |
| `autonomous-zero-baht` | Zero-cost content OS: RSS research → score → template drafts → validate → log. No publishing. |
| `autonomous-zero-baht-1` | The same OS, earlier/parallel branch. Treat `autonomous-zero-baht` as canonical unless told otherwise. |

All four are under `github.com/aerismusic8-alt`. A conversation is pinned to one
repository workspace; the others are cloned on demand (see environment).

## 4. Hard-won environment facts

The full list is in `references/environment.md`. These five waste the most time:

1. **`$HOME` is ephemeral; only `/workspace` survives a recycle.** Anything that
   must persist (browser profile, installed skills, state) goes under `/workspace`.
   `~/.agents/skills/` loads as *user-level* (every conversation) but is lost on
   recycle — restore it with `scripts/install-agent-skills.sh`.
2. **The sandbox `GITHUB_TOKEN` cannot write.** It is a GitHub App installation
   token with no write scope: every push is 403 and `workflow_dispatch` is 403.
   `GET /repos/...` reporting `push=true` is K's role, not the token's scope — do
   not trust it. Write access lives on PC1 (`scripts/push-via-pc1.sh`), and that
   route currently needs its auth fixed.
3. **Google Drive upload is blocked on all three routes** (Drive API disabled in
   the owning Cloud project; PC1 `/mcp` 401; desktop Google login expired). Plan a
   delivery channel *before* generating media — a pod-local URL dies on recycle.
4. **Login-only web apps need the cloud desktop.** Flow Music and Gemini web have
   no API. The operator signs in once via noVNC; the agent never types the password.
   Read the `ax-cloud-desktop` skill before touching either.
5. **The sandbox shell mangles `<<'EOF'` heredocs** (tab completion fires inside
   them). Prefer the file editor, or `printf '%s\n' 'line'`.

## 5. Delivery and verification

- **Decide the delivery channel first.** A finished artifact with no reachable
  destination is not finished. Confirm the channel works (Drive, release, PC1 push)
  before spending hours producing output.
- **Verify with evidence, not assertion.** Read the actual stream (`ffprobe`),
  the actual HTTP code, the actual test exit. Report numbers, not adjectives.
- **A red test must never reach a user.** The publish path sits after the tests.
- Serve a pack for review with a static server (`python3 -m http.server` on the
  session's `work-2-...` host), and say plainly that the link dies on recycle.

## 6. Operating loop

1. Read this skill, then the repository's own `AGENTS.md` and its `docs/GOAL.md`
   or `AKATH_CORE/` before planning.
2. State the plan and the delivery channel. Get K's confirmation before producing
   anything large or irreversible.
3. Do the smallest real thing that produces a verifiable result.
4. Verify, then record what was learned in `.openhands/memory/` and `AGENTS.md`.
5. If a route is blocked, exhaust it once, then report the block with evidence and
   the exact operator action needed — do not silently substitute a worse route.

## 7. Maintaining this skill

This skill is the account's shared memory of *how* work is done here; the repos'
own docs are the source of truth for *what*. When a rule changes, update it here
too. After a pod recycle, reinstall it for every conversation:

```bash
bash scripts/install-agent-skills.sh
```
