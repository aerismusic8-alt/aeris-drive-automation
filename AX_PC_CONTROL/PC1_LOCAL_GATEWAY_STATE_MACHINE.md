# PC1 Local Gateway State Machine

States:

1. UNKNOWN
   No fresh local evidence.

2. NOT_VERIFIED
   Gateway source exists but PC1 runtime evidence is absent or stale.

3. ALIVE
   Fresh GET /health proves the gateway is responding on PC1.

4. READY
   ALIVE plus local Brain heartbeat and Control heartbeat are fresh.

5. EXECUTING
   Brain intent accepted and Control has acknowledged execution.

6. VERIFIED
   Post-action evidence and verifier proof confirm the requested result.

Transitions:
UNKNOWN -> NOT_VERIFIED
NOT_VERIFIED -> ALIVE only from fresh PC1 /health evidence.
ALIVE -> READY only when Brain + Control local heartbeats are fresh.
READY -> EXECUTING only from a valid Brain intent.
EXECUTING -> VERIFIED only after post-action evidence and verification.
Any missing/stale/conflicting local evidence -> NOT_VERIFIED.

Important:
- GitHub workflow status cannot create ALIVE/READY/VERIFIED.
- ChatGPT messages cannot create ALIVE/READY/VERIFIED.
- Remote Desktop Commander cannot substitute for PC1-local evidence.
- Event diagnosis must remain local to the node where the event occurred.
