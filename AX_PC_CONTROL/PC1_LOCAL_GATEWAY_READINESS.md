# PC1 Gateway Readiness

A PC1 node may be marked READY only when all local evidence is fresh:

- Gateway /health response
- PC1 Brain decision heartbeat
- PC1 Control heartbeat
- Local node identity
- No unresolved evidence conflict

The readiness result must include:
- nodeId
- computerName
- checkedUtc
- heartbeat timestamps
- evidenceScope
- verification status

If any required item is missing or stale, state remains NOT_VERIFIED.
