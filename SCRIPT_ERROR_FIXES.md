# Script error fixes and recommendations

This file summarizes likely runtime errors found in the files introduced by PR #2 and provides concrete fixes to apply. I scanned the PR patchset and produced targeted recommendations for each script/workflow that commonly fail when executed on typical runners (Windows PowerShell 5.1 / GitHub Actions self-hosted / Cloudflare Workers runtime). Apply the suggested edits or I can open follow-up PRs if you want me to make the changes.

---

## 1) GitHub Actions workflows (several .github/workflows/*.yml)
Problem: Many workflow steps set `shell: powershell -ExecutionPolicy Bypass -File {0}` (or use `{0}` placeholder). This is not a valid `shell` value for GitHub Actions and appears to be a templating placeholder that will cause the runner to fail or treat the step incorrectly.

Suggested fix:
- Replace `shell: powershell -ExecutionPolicy Bypass -File {0}` with either `shell: pwsh` (recommended for cross-platform/powershell core) or `shell: powershell` (Windows PowerShell).
- Put the script invocation into the `run:` block, for example:
  - run: |
      & "$env:GITHUB_WORKSPACE\AX_AICS_PAPER_E2E.ps1"
    shell: pwsh
- If you need to pass the ExecutionPolicy for Windows PowerShell, use:
  shell: powershell
  run: |
    powershell -NoProfile -ExecutionPolicy Bypass -File "$env:GITHUB_WORKSPACE\AX_AICS_PAPER_E2E.ps1"

Why: `shell:` accepts the shell name (pwsh, bash, cmd, powershell) and optional shell options in a different structure — embedding `{0}` or `-File {0}` will break execution.

Files to update: `.github/workflows/aics-paper-e2e.yml`, `.github/workflows/aics-persistence-autosave.yml`, `.github/workflows/cloudflare-runtime.yml`, `.github/workflows/ax-executive-loop.yml`, etc.

---

## 2) PowerShell scripts using `-UseBasicParsing` (Invoke-WebRequest / Invoke-RestMethod)
Problem: `-UseBasicParsing` is removed in PowerShell Core (pwsh). If workflow uses `pwsh` (recommended), these calls will throw.

Suggested fix:
- Detect PowerShell edition and adapt the call. Example pattern:
  if ($PSVersionTable.PSEdition -eq 'Core') {
    # Use alternate parsing or avoid -UseBasicParsing
    $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec $TimeoutSec
  } else {
    $response = Invoke-WebRequest -Uri $url -Method Get -UseBasicParsing -TimeoutSec $TimeoutSec
  }
- Or remove `-UseBasicParsing` and rely on `Invoke-WebRequest` in Core-compatible mode; for robust cross-platform code consider using HttpClient from .NET or `curl`/`Invoke-RestMethod` which is more consistent.

Files to review: `AX_CLOUDFLARE_DISPATCH_ADAPTER.ps1`, `AX_AERIS_EXECUTION_ADAPTER.ps1`, `AX_ACTION_DISPATCHER.ps1`, `AX_HEARTBEAT_INSTALL.ps1`, others.

---

## 3) Use of `-TimeoutSec` parameter
Problem: `-TimeoutSec` is available in PowerShell Core and modern modules, but older Windows PowerShell builds may not accept it for some cmdlets. This can cause an "unbound parameter" error.

Suggested fix:
- If you need to support Windows PowerShell 5.1 and PowerShell Core, detect version and call with compatible parameters or use a wrapper that enforces a timeout using a separate Timer/HttpClient.
- Example compatibility wrapper:
  if ($PSVersionTable.PSVersion.Major -ge 6) {
    Invoke-RestMethod -Uri $u -Method Post -TimeoutSec 30 -Body $body
  } else {
    # fallback: use System.Net.Http.HttpClient with CancellationToken or omit timeout
    Invoke-RestMethod -Uri $u -Method Post -Body $body
  }

Files: multiple scripts that call `Invoke-RestMethod`/`Invoke-WebRequest` with `-TimeoutSec`.

---

## 4) Scripts that rely on `git` being present (AX_REPOSITORY_MUTATION_GATE.ps1)
Problem: `git` calls (`git branch --show-current`, `git add`, `git commit`, `git push`, `git remote get-url origin`) will fail if `git` is not installed or the working directory is not a repository.

Suggested fix:
- Add an early check: `if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'GIT_NOT_AVAILABLE' }`
- Verify `git rev-parse --is-inside-work-tree` before running operations and provide a helpful error message.
- Consider guard rails when running on CI vs local (CI may require different remotes or tokens). If running inside GitHub Actions, use the provided GITHUB_TOKEN rather than pushing with local credentials.

Also: compare $env:AX_REPOSITORY_MUTATION_ENABLED case-insensitively: environment values can be `true`/`True`/`1`. Use: `if ((($env:AX_REPOSITORY_MUTATION_ENABLED) -ne 'true') -and (($env:AX_REPOSITORY_MUTATION_ENABLED) -ne 'True')) { throw ... }` or better `if (-not ($env:AX_REPOSITORY_MUTATION_ENABLED -and $env:AX_REPOSITORY_MUTATION_ENABLED.ToLower() -eq 'true')) { throw ... }`.

File: `AX_REPOSITORY_MUTATION_GATE.ps1`.

---

## 5) ConvertTo-Json and ConvertFrom-Json cross-version differences
Problem: Some scripts use `ConvertTo-Json -Compress` or `-Depth 20` or `-Depth 10`. Older PowerShell versions behave differently and `-Compress` is not a parameter on older PS builds.

Suggested fix:
- Use `ConvertTo-Json -Depth 20` (without `-Compress`) for compatibility.
- To produce compact JSON across versions, use `-Depth` and then pipe to `-replace '\s+'` if necessary, or use `[System.Text.Json.JsonSerializer]::Serialize()` from .NET 5+ if available.

Files: `AX_PC2_WORKER_V2.ps1`, `AX_AERIS_EXECUTION_ADAPTER.ps1`, `AX_ACTION_DISPATCHER.ps1`, others.

---

## 6) AX_PC2_WORKER_V2.ps1: Node secret handling and Headers function
Observations:
- Headers function throws if $NodeSecret is empty but does not include NodeSecret in headers — you validate presence but don't include it in header. If the Node API expects a header (Authorization or X-Node-Secret), add it.

Suggested fix:
- If the API requires a header, add it: `return @{ Accept='application/json'; 'Content-Type'='application/json'; 'X-Node-Secret' = $NodeSecret }` or include `nodeSecret` in body consistently with server expectations.
- Add explicit JSON schema checks for server responses and avoid assuming properties exist.

File: `AX_PC2_WORKER_V2.ps1`.

---

## 7) Apps Script: AERIS_File_ID_Persistence_Patch.gs
Potential runtime issues:
- `getQueueSheet()` must exist in the same project. If not, add a guard and a helpful error message.
- JSON.parse may throw on malformed `Result` cells — you already try/catch and continue, which is good. Consider logging which rows were skipped for future debugging.

Suggested fix:
- Add `if (typeof getQueueSheet !== 'function') { throw new Error('getQueueSheet missing in project'); }`
- Add `Logger.log()` calls with row index when skipping rows due to parse errors.

File: `AERIS_File_ID_Persistence_Patch.gs`.

---

## 8) Cloudflare Worker (cloudflare/ax-control-runtime/src/index.ts)
Potential runtime errors and improvements:
- `verifyGitHubToken` calls GitHub API root repo endpoint. Make sure the token has repo read permission. If using GITHUB_TOKEN inside a Worker, that token must be provided securely (do not hardcode). If token is large, you already cap length; good.
- After calling `env.AX_EXECUTION_QUEUE.send(normalizedEvent)` ensure that binding name `AX_EXECUTION_QUEUE` exists in wrangler.jsonc and that the queue binding is present in the Worker environment.
- The queue consumer handler throws an Error when AERIS execution is not verified. A thrown Error inside a queue consumer will likely cause message retry and can exhaust queues. Prefer to `message.nack()` or route to DLQ and log, instead of throwing.

Suggested fixes:
- Replace `throw new Error(...)` inside `queue(...)` with `console.error(...)` + decide whether to ack or nack message. Example: if transient, `message.nack()`, if irrecoverable, `message.ack()` and emit a structured error event.
- Add try/catch around the `await env.AX_EXECUTION_QUEUE.send(...)` with exponential retry logging to handle transient Cloudflare/Network errors.

Files: `cloudflare/ax-control-runtime/src/index.ts` and `wrangler.jsonc`.

---

## 9) Generic recommendations
- Add a CI step that runs PowerShell linting (PSScriptAnalyzer) and a smoke-run for the TypeScript build to catch these errors on PRs.
- Record runtime versions in the workflow (pwsh vs powershell, PowerShell version, Node.js version) at the start of the job to ensure cmdlet parameter compatibility.
- Add defensive checks for external program availability (git, npx, wrangler) and provide actionable errors.

---

If you'd like, I can:
- Apply the trivial fixes to the workflows (replace `shell:` lines) and push a commit to `main` (requires permission).
- Open issues for the remaining suggested changes so you or your team can triage them.

What I did: I scanned PR #2's added files and wrote these consolidated recommendations.

If you want me to push the recommendations file into the repository and/or create issues/PRs with the concrete edits, tell me and I will apply them (I have the repo name: aerismusic8-alt/aeris-drive-automation).
