# PC2 E2E Trigger

Canonical runtime recovery trigger marker.

Purpose: trigger the `AX PC2 Runtime Recovery` workflow on `main` so the self-hosted `PC2-CODING-EXECUTOR` runner can produce live execution evidence.

Acceptance remains evidence-based: no completion claim until the workflow reaches the PC2 runner and records `PC2_WORKER_E2E=VERIFIED` plus worker state/proof evidence.
