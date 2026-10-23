---
name: ax-pc1-ops
description: Operate and diagnose the PC1 self-hosted runner, winremote MCP, and the AX GitHub workflows for aeris-drive-automation. Use when a PC1 workflow fails, queues forever, or PC1 must be reached, repaired, or proven alive.
triggers:
- pc1
- runner
- desktop control
- winremote
---

# Operating PC1 and the AX workflows

Every claim in this file was observed in this repository. Dates are UTC.
When a step here disagrees with what you see, believe what you see and
update this file.

## Split the failure before you fix anything

A red run on `runs-on: self-hosted` has three very different causes. They
look identical in the UI and each needs a different fix. Decide which one
you have *first*.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `queued`, no runner assigned, minutes pass | runner service stopped, or registered to another repository | someone starts it on PC1 |
| job starts, then fails at ~10 min, `steps: []`, job log `BlobNotFound` | runner cannot run jobs at all | repair runner on PC1 |
| job starts, steps run, one step red | your change | read that step |

The middle row is the expensive one. It looks like a script bug and is not.
**It is not your code.**

### The discrimination test that settles it

Before you touch a script, rerun a job that already succeeded:

```bash
gh run list --repo <owner>/<repo> --limit 10     # find a green run id
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/<owner>/<repo>/actions/runs/<GREEN_ID>/rerun"
```

If the green job now fails with `steps: []`, the runner is broken and no
edit to your script can matter. Measured 2026-10-23: a previously green
`AX PC1 Desktop Control` job failed on rerun after 10 min 1 s with zero
steps. That single call replaced hours of script archaeology.

The 10-minute figure is the tell. A runner that dies at setup reports
`steps: []` and the job log URL answers `BlobNotFound`, because no log
was ever written.

## Reading the queue, not the runner API

`GET /repos/{owner}/{repo}/actions/runners` returns **403** for the
GitHub App installation token. Do not spend time on it. The queue is the
signal:

```bash
gh run list --repo <owner>/<repo> --limit 8 \
  --json databaseId,name,status,conclusion,createdAt
```

Compare a `queued` run's age against a recent run that finished in
seconds. Queue with no progress while the same runner was fast minutes
ago means the runner is down.

## PC1 liveness is three separate questions

Do not collapse them. Each has its own evidence.

1. **Is the machine reachable?**

   ```bash
   curl -s -o /dev/null -m 15 -w "http=%{http_code} time=%{time_total}s\n" \
     https://desktop-rgk6jkb.tail8740ad.ts.net/health
   ```

   `200` means the tailnet Funnel and the proxy are up.

2. **Is the MCP service behind it answering?**

   ```bash
   curl -s -o /dev/null -m 15 -w "http=%{http_code}\n" \
     https://desktop-rgk6jkb.tail8740ad.ts.net/mcp
   ```

   **`401` is healthy.** It means the service is running and asking for a
   token. `000` after 20 s is down. `502` is the proxy up and the upstream
   on `127.0.0.1:8090` still booting. Do not read `401` as an outage —
   measured 2026-10-23, both endpoints answered while the *runner* was
   broken, and a memory note claiming "PC1 DOWN" was simply wrong.

3. **Is the runner taking work?** Only the queue answers this. A live
   machine with a dead runner is the common case.

`8090` and `8091` are loopback only. Only `443` is public.

## `git push` prompts for a password

The remote can carry a stale, read-only token baked into its URL. The
symptom is an interactive `Password for 'https://ghs_...@github.com':`
prompt that hangs a non-interactive shell, not a clean 403.

```bash
export GIT_TERMINAL_PROMPT=0                 # fail instead of hanging
TOKEN=$(node scripts/gh-app-token.mjs | head -1)
git remote set-url origin \
  "https://x-access-token:${TOKEN}@github.com/<owner>/<repo>.git"
git push --dry-run origin HEAD:refs/heads/<branch>
```

Always set `GIT_TERMINAL_PROMPT=0` first. A hang costs the full timeout;
a refusal costs nothing. Re-run `gh-app-token.mjs` per command — the
token lives about 30 minutes.

## Dispatch needs the app token

`gh workflow run` uses `GITHUB_TOKEN` from the environment, which is a
read-only App installation here and returns **403** on dispatch. Use the
app token and the REST endpoint:

```bash
TOKEN=$(node scripts/gh-app-token.mjs | head -1)
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
  "https://api.github.com/repos/<owner>/<repo>/actions/workflows/<file>.yml/dispatches" \
  -d '{"ref":"<branch>","inputs":{...}}' -w "HTTP=%{http_code}\n"
```

`204` is success. The same token reads artifacts; `gh` reads run lists
fine.

## Long work does not fit in an MCP call

The winremote MCP Shell tool has a **30 s** limit and runs in a **service
session with no interactive desktop**. Consequences:

- A capture or a Studio launch must run as a real workflow step, or as a
  scheduled task registered with `-LogonType InteractiveToken`.
- Anything that must draw a window cannot run inside the MCP tool call.
- `AX_PC_CONTROL/pc1-interactive-foreground.ps1` is the working pattern:
  the workflow creates the scheduled task and the *task* does the work.

A capture that runs in the runner's session photographs the runner's
session, not the desktop. Count only frames whose foreground process is
the target, or you will upload a picture of a browser and call it proof.

## Fetch scripts by SHA, not by branch

`raw.githubusercontent.com` sends `cache-control: max-age=300` and a
cache-busting query does not defeat it. A workflow that fetches
`.../<branch>/script.ps1` can run the previous revision for five minutes
after a push, which reads as "my fix did nothing".

Pin to the commit SHA, which cannot be stale:

```
https://raw.githubusercontent.com/<owner>/<repo>/$env:GITHUB_SHA/<path>
```

Have the script print a version marker as its first output so the run
itself says which build executed.

## Skills and memory: what actually persists

Measured 2026-10-23, and it corrects a popular theory:

- **`sandbox_grouping_strategy: GROUP_BY_NEWEST` is set and persists.**
  It is a real setting and it does make conversations reuse the newest
  sandbox, so `/workspace/project/` is shared between them.
- **Sharing a filesystem is not the same as loading a skill.** A file at
  `.agents/skills/<name>.md` inside the repo is *not* injected into
  `<available_skills>` for the next session. The directory
  `/workspace/project/aeris-drive-automation/.agents/` did not exist at
  all when this was checked.
- **`memory_context` is real and populated** (11,649 chars) and its
  headings do appear to the agent. It is re-resolved per session, so it is
  a durable place to leave notes.
- **Inline `agent_settings.agent_context.skills` is a replace, not an
  append.** Writing it can silently delete existing skills. Back up
  settings before writing:

  ```bash
  curl -s -H "Authorization: Bearer $OPENHANDS_API_KEY" \
    "https://app.all-hands.dev/api/v1/settings" \
    -o /tmp/ohbackup/settings-$(date +%H%M).json
  ```

So: keep durable operational knowledge in **this repository** — `AGENTS.md`
and `.agents/skills/` — and treat it as the source of truth. Do not
believe a note that says a skill is loaded until a fresh session lists it
in `<available_skills>`.

## Reporting a failure

State which of the three causes you proved, and the evidence that proved
it. "Runner is broken" and "my script is broken" are different claims, and
the rerun test is what separates them. A run that fails with zero steps
says nothing about the code it would have run.
