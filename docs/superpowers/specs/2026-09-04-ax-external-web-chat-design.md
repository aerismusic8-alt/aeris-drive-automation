# AX External Web Chat Design

## Goal
Provide AX with a browser-accessible external chat surface without exposing the Local AX Control Hub, A_MASTER_BRAIN, GitHub credentials, or the existing execution runtime directly to the public internet.

## Authority and boundaries
- K remains Final Authority.
- A_MASTER_BRAIN remains the only authoritative source of identity, mission, tasks, state, evidence, and verification.
- `ax-control-runtime` is transport/control only; it must not become a competing state store.
- Local `AX_CONTROL_HUB` remains the execution-facing boundary on the controlled PC.
- `aeris-execution-runtime` remains a separate execution boundary and is not merged into the AX gateway.
- Live financial execution remains disabled (`FREE_ONLY`).

## External flow
1. Browser opens `https://ax-control-runtime.aerismusic8.workers.dev/chat`.
2. Browser submits text/file/image metadata through an authenticated external session mechanism; raw credentials are never sent to GitHub or embedded in client code.
3. Worker writes a transport record to `AX_GATEWAY_INBOX`.
4. Controlled PC bridge polls `/pc/pull` using `AX_PC_PULL_SECRET`.
5. Bridge sends the request to Local Hub `/gateway/input` using Local Hub credentials held only on the PC.
6. Bridge posts the Local Hub response to a result endpoint on the Worker and acknowledges the original request.
7. Browser polls the result endpoint and renders authoritative status/evidence fields returned by the Local Hub.

## Authentication
The public browser must not receive or persist `AX_PC_PULL_SECRET`, GitHub tokens, or Local Hub passwords. The external chat surface will use a dedicated browser/session credential boundary rather than reusing the PC secret.

## Transport data
Browser-visible payloads are metadata-safe. Attachments remain references only; raw binary/data is not written into A_MASTER_BRAIN state. Requests carry request IDs, task IDs, source channel, content type, content, attachment references, and status fields.

## Result lifecycle
The Worker keeps a short-lived correlation record for each external request with states such as `RECEIVED`, `CLAIMED`, `SUBMITTED`, `COMPLETED`, or `FAILED`. Completion claims require the Local Hub response's verification/evidence fields; the gateway never upgrades `QUEUED` into `EXECUTING` or `COMPLETED` by itself.

## Web UI
The external UI should reuse the usability model of `AX_CONTROL_HUB/operations.html`: authenticated session, context/status panel, message composer, attachment metadata, M-A-CHECK, refresh, and logout. It should be mobile-first and responsive, but it must call the Worker routes instead of local `/gateway/*` routes.

## Required Worker additions
- `/chat` HTML surface.
- Dedicated external session/login boundary.
- Correlated result read endpoint.
- Safe error contract.
- No new master-state store.

## Required bridge additions
- Forward the Local Hub response back to the Worker before ACK.
- Preserve request/task IDs and verification/evidence state.
- Never expose Local Hub credentials or secrets in returned payloads or logs.

## Acceptance criteria
- Existing AX External Channel Readiness remains green.
- `/chat` is reachable externally.
- External chat request reaches the PC bridge and Local Hub.
- Browser receives the correlated Local Hub response.
- M-A-CHECK and context retrieval use authoritative Local Hub data.
- Unauthenticated external requests are rejected.
- No GitHub or PC secret is shipped to the browser.
- `FREE_ONLY` and `liveFinancialExecution=false` remain enforced.
