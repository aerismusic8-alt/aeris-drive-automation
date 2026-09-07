# AKATH Self-Managed Execution & External Dashboard Design

## Goal
Keep AKATH/AX operational when GitHub-hosted Actions minutes are exhausted by making self-hosted execution the default, routing work across available AI executors, and serving the read-only dashboard outside GitHub Actions.

## Approved Architecture
- AX is the executive orchestrator and owns mission routing/recovery decisions.
- AX_MISSION_LEDGER is the persistent source of truth for mission/task lifecycle.
- AX_EXECUTION_QUEUE is the transport for execution events.
- PC1/PC2 self-hosted runners are the primary execution substrate.
- AI helpers (OpenAI, Gemini API, Gemini Live Code Stream, and future providers) are selectable executors by capability and availability.
- Cloudflare remains the ingress/state boundary.
- The dashboard is observation-only and must not be required for execution.

## Operating Rules
1. GitHub-hosted runners must not be required for ordinary AX execution while the Actions budget is $0.
2. Scheduled execution must use self-hosted runners.
3. Nonessential validation/deployment workflows must not auto-trigger on every main push when they require hosted runners.
4. AI-provider failure is a reroute/retry/failover condition, not a mission-terminal condition.
5. A mission is successful only when it reaches COMPLETED + VERIFIED with durable evidence.
6. Transport/context changes must not create duplicate execution for the same logical command.
7. The dashboard must not become an execution dependency.

## Dashboard Deployment
Use an external static hosting target (prefer the existing Cloudflare estate; Vercel is an acceptable fallback) so dashboard availability is independent of GitHub Actions minutes. The dashboard consumes public/read-only runtime state and must not expose secrets.

## Acceptance Criteria
- No required/scheduled production workflow uses ubuntu-latest or windows-latest.
- No 5-minute polling workflow remains on a GitHub-hosted runner.
- Core AX execution continues through self-hosted PC1/PC2.
- Existing queue/ledger semantics remain intact.
- Dashboard has a verified public URL outside Actions.
- At least one real queued mission can be traced through execution and verification without a manual K prompt between stages.
