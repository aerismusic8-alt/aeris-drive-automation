# AKATH Runtime

**AKATH — Autonomous AI Company**

AKATH is the company layer above the existing A MASTER BRAIN / AX execution substrate.

This directory contains the GPT-independent autonomous runtime contract and proof harness. ChatGPT remains a K-facing control/observation channel; ordinary job continuation must not depend on chat interaction.

## Runtime flow

```text
Trigger → A MASTER BRAIN / AX → Job → Execute → Verify → Persist → Next Job
```

## Status

- Design: approved
- Implementation branch: `akath-v1-autonomous-runtime`
- Runtime verification: not yet complete

See `RUNTIME_CONTRACT.md` and `tests/e2e-proof.md` for acceptance criteria.