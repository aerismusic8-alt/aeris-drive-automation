# PC1 Local Brain Gateway State Contract

Authority: PC1_LOCAL_BRAIN.
GitHub is source/version control only.

State progression:
UNKNOWN -> NOT_VERIFIED -> ALIVE -> READY -> EXECUTING -> VERIFIED

Rules:
- UNKNOWN/NOT_VERIFIED: no fresh local evidence.
- ALIVE: PC1 identity matches and local gateway /health is fresh.
- READY: ALIVE plus fresh PC1 Brain and PC1 Control heartbeats.
- EXECUTING: READY plus a valid Brain-approved intent has been accepted.
- VERIFIED: EXECUTING plus fresh post-action evidence and verification.

Evidence locality:
- Runtime evidence must originate on PC1.
- Remote observations cannot promote PC1 to READY or VERIFIED.
- Evidence from another node is EVIDENCE_NOT_LOCAL_TO_EVENT.

Intent authority:
- Brain selects the intent.
- Gateway transports and validates the intent.
- Control executes the intent.
- Verifier validates the result.
- Gateway never selects or changes an intent.

Failure:
- Identity mismatch, stale/missing heartbeat, malformed intent, conflicting evidence, or missing post-action proof returns NOT_VERIFIED/FAILED as applicable.
- No success state may be inferred from GitHub workflow completion alone.

Recovery:
- Brain diagnoses locally.
- Control repairs locally.
- Verifier captures post-repair evidence.
- The resulting cause/fix/prevention record is written to the Master Brain.