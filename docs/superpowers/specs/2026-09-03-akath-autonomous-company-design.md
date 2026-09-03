# AKATH Autonomous Company Architecture v1

**Status:** Approved by K for implementation

## Identity

**AKATH**

**Corporate description:** Autonomous AI Company

AKATH is the company-level identity. A MASTER BRAIN is the authoritative strategic/knowledge brain. AX is the executive orchestration layer. AI workers, connectors, and execution nodes operate below AX.

## Objective

Build AKATH as an autonomous business operating system that can continuously create, execute, verify, learn, and advance work without requiring GPT Chat to remain in the execution critical path.

The first acceptance test is continuous autonomous operation: `Trigger → A MASTER BRAIN / AX → Job → Execute → Verify → Log → Next Job` must be able to repeat without a K message between ordinary jobs.

## Architecture

```text
K
│
├── ChatGPT / Control Interface
│      └── command / observe / approve / override
│
▼
A MASTER BRAIN
│
▼
AX — Executive Orchestrator
│
├── Mission / Priority
├── Task Registry
├── Routing
├── Permission / Risk Gate
└── PCSEV
│
▼
AKATH AUTONOMOUS RUNTIME
│
├── Trigger / Scheduler
├── Persistent Queue / State
├── GitHub Actions
├── Self-hosted Runner(s)
└── Recovery / Heartbeat
│
▼
AI WORKFORCE + EXTERNAL CONNECTORS
│
├── AI agents
├── Content systems
├── Product systems
├── Service systems
└── Business APIs
│
▼
VERIFY → EVIDENCE → AUDIT LOG
│
▼
NEXT JOB / CONTINUE
```

## Core rule: Chat is not runtime

ChatGPT remains a supported K-facing control and observation channel. It must not be required to pass ordinary autonomous jobs from one execution cycle to the next.

GPT Free limitations must therefore not stop the autonomous execution loop.

## Execution substrate

The existing repository `aerismusic8-alt/aeris-drive-automation` remains the initial execution substrate. Existing Control Hub contracts, A MASTER BRAIN authority, task state, evidence semantics, runners, and verification mechanisms are preserved unless a measured change is required.

GitHub Actions is the orchestration/execution bridge; self-hosted runners are preferred for continuous local execution because GitHub documents self-hosted Actions usage as free while the operator remains responsible for the machine. GitHub-hosted private-repository minutes remain subject to account quotas/billing.

A scheduled workflow may provide a periodic wake-up, but continuous operation must not depend on a single scheduled event. Runner-level supervisor/heartbeat and persisted state are required for recovery.

## 24/7 acceptance criteria

A build is not considered 24/7 verified until evidence shows all of the following:

1. A trigger starts the runtime without a GPT Chat message.
2. AX obtains the next valid job from authoritative state/queue.
3. Execution occurs on a configured runner.
4. Completion is verified with evidence.
5. The next job is selected automatically.
6. A transient failure produces recovery behavior rather than silent stoppage.
7. Heartbeat/state evidence proves the loop remains alive across multiple cycles.
8. K can inspect status from ChatGPT without being required to advance the loop.

## Revenue architecture

AKATH will initially prioritize low/no recurring tool cost channels:

1. AI services
2. Digital products
3. Content-to-product distribution
4. Affiliate/referral revenue
5. Platform monetization such as YouTube when eligibility is met
6. Music/IP as a business unit
7. Later SaaS/AI products after cash flow exists

Revenue channels are adapters above the same autonomous runtime rather than separate orchestration systems.

## Integration principle

External systems must connect through an integration/adapter layer. AX should consume stable logical capabilities such as `READ`, `CREATE`, `UPDATE`, `PUBLISH`, `VERIFY`, and `LOG`, while vendor-specific details remain inside adapters.

This lets AKATH begin with free/manual/semi-automated connectors and later replace or add paid APIs without redesigning AX.

## Safety and authority

K remains Final Authority. High-risk actions, financial execution, permission expansion, and major architecture changes require explicit authorization. Autonomous operation does not grant the system new permissions.

## Success definition

AKATH v1 succeeds when the existing system can demonstrate a continuously advancing, evidence-backed execution loop that is independent of GPT Free as a runtime dependency, while preserving ChatGPT as a control/observation channel for K.