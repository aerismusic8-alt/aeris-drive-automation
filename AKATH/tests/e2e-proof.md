# AKATH Autonomous E2E Proof

## Required proof

A cycle is verified only when the worker itself records `verification_status=VERIFIED` and an evidence reference exists.

A 24/7 runtime claim requires multiple successive verified cycles initiated without a ChatGPT message between them.

## Current test mode

`AKATH_PROBE_MODE=true` is a harmless proof mode. It performs no financial, public publishing, or production-secret side effects. It proves runtime wake-up, exclusive lease behavior, state persistence, verification, and readiness for a next cycle.

## Evidence to collect

| Cycle | GitHub run | Runtime run | Job | Verification | Next job |
|---|---|---|---|---|---|
| 1 | pending live run | pending | pending | pending | pending |
| 2 | pending live run | pending | pending | pending | pending |
| 3 | pending live run | pending | pending | pending | pending |

Overall status is `NOT VERIFIED` until direct workflow evidence populates all required cycles.