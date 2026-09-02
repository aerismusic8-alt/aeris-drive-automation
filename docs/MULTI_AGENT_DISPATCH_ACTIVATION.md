# Multi-Agent Dispatch Activation

Status: APPROVED FOR IMPLEMENTATION
Authority: K_FINAL_AUTHORITY

## Objective
Reduce execution bottlenecks by routing eligible work to verified AI workers without stopping existing workloads.

## Agents
- A: orchestration, priority, dependency and final decision authority
- M: continuity, evidence and operational support
- Gemini: research, Google-oriented operations, analysis and QC where a verified connector exists
- Copilot: Microsoft-oriented operations, coding/review and backup QC where a verified connector exists
- AX/Cloud: execution workloads supported by verified runtime
- PC2: specialized local workloads and fallback

## Routing rules
1. Dependency-safe selection remains mandatory.
2. Prefer parallel execution for independent tasks.
3. A worker is eligible only when its capability and execution channel are verified.
4. Queue acceptance, heartbeat, model response, or proof-artifact creation alone do not constitute business completion.
5. Completion requires real business-result evidence, verification, and task-state write-back.
6. No live financial execution.
7. Existing running jobs must not be stopped solely to activate this layer.
8. Unknown/unverified connectors remain DISABLED rather than inferred as operational.

## Activation stages
1. Discover existing Gemini/Copilot connectors and capability declarations.
2. Add capability-aware routing without bypassing the canonical dependency selector.
3. Add regression tests for routing and evidence gates.
4. Activate only verified routes.
5. Verify end-to-end business execution and state write-back.
