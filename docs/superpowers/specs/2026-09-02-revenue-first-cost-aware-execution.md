# Revenue-First Cost-Aware Execution Architecture

**Date:** 2026-09-02
**Authority:** K (Final Authority)
**Status:** APPROVED FOR IMPLEMENTATION

## Goal
Make revenue generation the primary optimization target while minimizing pre-revenue operating cost, removing PC2 self-hosted runner availability as a universal bottleneck, and preserving Evidence → Verify requirements.

## Architecture
Use a hybrid execution model. Cloud execution is the preferred path for lightweight, event-driven, revenue-producing work when the existing Cloudflare infrastructure can execute the real business action and produce verifiable evidence. PC2 remains a specialized/local worker for jobs that genuinely require the local environment. GitHub-hosted runners are a temporary fallback for bounded CI/automation work when their free allowance makes them cost-effective; they are not the business execution source of truth.

## Economic Rules
1. Default incremental infrastructure spend is ฿0 until revenue or a measured ROI case justifies spend.
2. Existing free/paid infrastructure must be measured before adding another service.
3. A faster executor is not preferred if it only accelerates proof-artifact generation rather than real business execution.
4. Any recurring cost must have a defined business purpose, usage ceiling, and revenue/ROI justification.
5. Revenue-producing execution has priority over infrastructure expansion that does not directly unblock revenue.
6. Financial/live-money execution remains disabled until its existing technical, security, compliance and K-approval gates are satisfied.

## Execution Policy
- Canonical task selection remains dependency-safe.
- Dispatcher must select only eligible tasks.
- Business execution must produce execution evidence tied to task ID.
- Completion requires verified business-result evidence and task-state write-back.
- Heartbeats, queue acceptance, adapter proof artifacts, and runner activity are not sufficient evidence of business completion.
- PC2 outage must not stop cloud-eligible revenue work.
- Jobs requiring PC2 may wait for PC2 and must be explicitly classified as PC2-dependent.

## Cost Model
Measure at minimum:
- Cloudflare Worker requests and CPU time.
- Cloudflare Queue operations.
- GitHub Actions minutes and storage.
- PC2 incremental monetary cost (electricity/maintenance only when material and measurable).
- Any future VPS/VM cost.

Use current vendor pricing as external reference, but use actual account usage as the source for the system's internal cost ledger.

## Success Criteria
The architecture is successful only when all of the following are demonstrated:
1. A revenue task can be selected without violating dependencies.
2. A cloud-eligible task can execute without waiting for PC2.
3. The execution performs a real business action, not only a self-generated proof artifact.
4. Evidence is persisted and independently verifiable.
5. Task state is written back with trusted execution timestamps.
6. The incremental infrastructure cost is known or bounded.
7. The first revenue-producing path is prioritized ahead of non-revenue infrastructure work.
8. If cloud execution cannot meet these criteria, the system routes the task to an appropriate worker rather than pretending it completed.

## Initial Scope
First inspect and instrument the existing AX Dispatcher → Control Runtime → Queue → AERIS Runtime path and the PC2 path. Do not introduce a paid VPS or other recurring infrastructure before this measurement and execution-proof stage passes.
