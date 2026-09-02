# Multi-Agent Dispatch Design

**Goal:** Add Gemini and Microsoft Copilot as evidence-gated auxiliary workers so eligible work can run in parallel without bypassing A MASTER BRAIN authority, dependencies, or verification.

## Scope
- Discover and register actual Gemini/Copilot execution capabilities.
- Route only tasks whose required capability is available and whose dependencies are satisfied.
- Preserve A as orchestrator and K as final authority.
- Require execution evidence, verification, and task-state write-back before completion.
- Keep financial/live-money execution disabled.
- Do not stop existing queued/running work while the new routing layer is introduced.

## Architecture
A remains the control plane. A task selector classifies work by capability and dependency, then dispatches eligible work to Gemini, Copilot, AX/cloud, or PC2. Agent adapters must expose a common contract: accept task, execute real work, return evidence, verification result, and durable result reference. A failed/unavailable agent is treated as unavailable capacity, not as success.

### Agent roles
- **A:** orchestration, priority, dependency, final decision.
- **M:** continuity/evidence/operations support; never replaces A as source of truth.
- **Gemini:** research, Google ecosystem, analysis, QC, and other verified capabilities discovered in the existing connector path.
- **Copilot:** Microsoft ecosystem, coding/review/QC, and other capabilities discovered from actual integration evidence.
- **AX/cloud workers:** lightweight event-driven execution where real business execution is supported.
- **PC2:** specialized/local execution and fallback.

### Common execution contract
`TASK_OFFERED -> ACCEPTED -> EXECUTING -> RESULT -> EVIDENCE -> VERIFIED -> WRITE_BACK`

Heartbeat, queue acceptance, connector availability, or proof-artifact creation alone do not count as business completion.

### Routing classes
- `CLOUD_PREFERRED`
- `GEMINI_PREFERRED`
- `COPILOT_PREFERRED`
- `PC2_REQUIRED`
- `WAITING_K`

Routing must be capability-driven, dependency-safe, and cost-aware. No hidden paid resource activation.

## Safety / continuity constraints
1. Existing jobs remain running unless their own system reports failure or completion.
2. New routing must not duplicate a task already executing.
3. A dependent task cannot run until every dependency is verified COMPLETED.
4. Financial/live-money actions remain disabled.
5. No task is marked COMPLETED from a heartbeat or synthetic verification artifact.
6. Every agent result must be attributable to a task and durable evidence reference.
7. If Gemini or Copilot cannot be proven executable, they remain `AVAILABLE_FOR_REVIEW`, not active workers.

## Success criteria
- Gemini and Copilot capability status is derived from actual integration evidence.
- At least one non-conflicting eligible task can be routed to each agent only if real execution capability exists.
- Parallel execution does not violate dependencies.
- Completion requires verified business-result evidence and state write-back.
- Existing queued/running work is not interrupted by the new layer.
- Regression tests prove unsafe routing is rejected.
