# Multi-Agent Dispatch Implementation Plan

1. Inventory Gemini and Copilot connectors, capability declarations, and existing delegation paths.
2. Define a capability-aware route contract: CLOUD_PREFERRED, PC2_REQUIRED, GEMINI, COPILOT, WAITING_K.
3. Integrate routing with the canonical dependency-safe task selector.
4. Add tests that reject unverified agent routes and preserve running jobs.
5. Require execution evidence, business-result evidence, verification, and task-state write-back.
6. Activate only routes with verified execution channels.
7. Run end-to-end verification before marking any task COMPLETED.

This plan does not authorize live financial execution and does not stop existing workloads.
