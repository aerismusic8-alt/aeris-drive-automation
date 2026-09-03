# Contract Validation

This document is the executable review checklist for the v1 runtime contract.

## PASS cases

- `READY → RUNNING → VERIFIED`
- `RUNNING → WAITING`
- `RUNNING → RECOVERING → RUNNING`
- `RUNNING → FAILED`
- verification evidence exists before `VERIFIED`

## FAIL cases

- `health=OK` without execution evidence must not become `VERIFIED`
- queued work must not become `RUNNING` without a lease/execution event
- completion must not become `VERIFIED` without evidence
- recovery must not silently convert an unknown outcome to success
- ChatGPT presence/absence must not alter runtime state transitions
