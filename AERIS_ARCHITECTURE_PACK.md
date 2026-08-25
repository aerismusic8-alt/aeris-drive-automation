# AERIS Architecture Pack

## Purpose
Canonical architecture package for AERIS MUSIC / AX External Execution Runtime. This package is the source material to be persisted into the AERIS Google Drive 8-folder taxonomy through the verified AERIS Drive Automation path.

## Authority
- K: Final Authority for approvals, high-risk actions, spending, and major architecture changes.
- AX: AI Executive Orchestrator operating within granted permissions.

## Verified Baseline
- Gate 3.3.2 is the immutable verified baseline.
- Do not modify or regress the verified EXECUTE_EXTERNAL -> Cloudflare Runtime -> Gemini -> verified completion path while extending Dispatcher capabilities.

## 8-Folder Canonical Taxonomy

### 01 IDENTITY & ACCOUNTS
Purpose: organizational identity, service identities, account ownership, system identity records, and non-secret account references.

### 02 AI TEAM
Purpose: AX, MUSE, Gemini, Copilot, Perplexity, NOVA roles, capabilities, routing policy, and agent registry documentation.

### 03 HQ & KNOWLEDGE
Purpose: MASTER HQ, architecture records, canonical system knowledge, savepoints, state snapshots, recovery documentation, and verified system baselines.

### 04 WORKFLOWS & DISPATCH
Purpose: queue workflows, delegation, Dispatcher, node protocol, registration, trust, heartbeat, job pull, lease, ACK, retry, fallback, and execution routing.

### 05 PERMISSIONS & APPROVALS
Purpose: permission boundaries, approval gates, K authority model, execution policies, high-risk controls, and approval records.

### 06 QC & ERROR RECOVERY
Purpose: verification rules, QC, error taxonomy, retry, fallback, incident records, regression checks, and recovery procedures.

### 07 AUTOMATION ROADMAP
Purpose: phased automation roadmap, runtime evolution, integration roadmap, and future AX/AICS architecture planning.

### 08 MASTER WORKFLOW
Purpose: canonical end-to-end operating workflow from goal intake through planning, dispatch, execution, verification, persistence, audit, and next action.

## Master Runtime Model
AX -> Control Plane -> Dispatcher -> Execution Node -> Verified Result -> Control Plane -> AX

## Control Plane
- Persistent job queue
- Delegation queue
- Approval / permission controls
- Savepoint / state recovery
- Audit / job logging
- Verification-first completion semantics

## Dispatcher Layer
- Node registration
- Persistent trust
- Heartbeat
- Capability routing
- Job pull
- Lease / concurrency control
- ACK / completion
- Retry / fallback

## Execution Fabric
Supported execution paths include Apps Script, Cloudflare Runtime, Gemini, and future external nodes. External execution must return evidence sufficient for verification before a job becomes COMPLETED.

## Operating Rule
Never claim an action is complete without verified evidence. Preserve passed components and avoid unnecessary architectural rewrites.

## Long-Term Direction
AERIS Runtime is the execution substrate for AX. The same control, permission, verification, audit, and risk architecture is intended to support the future AX Investment Control System (AICS) for market data, analysis, paper trading, and eventually controlled broker/exchange execution under K authority.

## Drive Persistence Protocol
1. Treat this package as the canonical source material.
2. Persist the relevant sections into the matching AERIS Drive folders 01-08.
3. Use the verified AERIS Drive Automation execution path rather than manual unverified writes where possible.
4. Read back every created/updated artifact.
5. Mark persistence successful only after read-back verification.
6. Record resulting file IDs, timestamps, and verification status in the AERIS job/audit log.
