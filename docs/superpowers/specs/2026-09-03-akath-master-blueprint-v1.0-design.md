# AKATH MASTER BLUEPRINT v1.0 — Architecture Design

**Status:** APPROVED DESIGN / SPEC REVIEW REQUIRED BEFORE IMPLEMENTATION
**Date:** 2026-09-03
**Company:** AKATH
**Corporate description:** Autonomous AI Company
**Final Authority:** K
**Executive Orchestrator:** A
**Primary operating principle:** Start every business from zero; leverage accumulated system experience and verified lessons as a starting advantage.

> This document defines the approved target architecture for the new AKATH company. It is an architectural specification, not an implementation claim. No runtime component is considered migrated, rebuilt, online, autonomous, or revenue-generating merely because it is described here.

## 1. Foundational Decisions

1. AKATH is the new company and primary corporate structure.
2. AERIS is legacy context only and is not the AKATH company structure.
3. AERIS-era blueprints are not authoritative for AKATH. They may be retained only as isolated legacy references for lessons learned after review.
4. AKATH begins new businesses from zero rather than assuming existing customers, revenue, audience, or business assets.
5. System experience, verified engineering lessons, PCSEV practice, and reusable patterns begin from the accumulated baseline rather than zero.
6. Initial investment capital is **฿0**.
7. The first economic objective is to create revenue quickly enough to cover necessary operating costs such as electricity, internet, tools, and required infrastructure.
8. Investment and asset allocation begin only after the company has sustainable operating cash flow and surplus capital under approved financial controls.
9. K is the final authority and should perform the minimum practical manual work necessary for governance and high-value decisions.
10. A is the central executive orchestrator and is responsible for managing the company within K-approved authority boundaries.
11. All AI workers, tools, connectors, and business units operate below A's executive control.
12. PCSEV is the core company control doctrine: Problem → Cause → Solution → Execute → Evidence → Verify, followed by learning and standardization where appropriate.

## 2. Authority Model

```text
K — FINAL AUTHORITY
        |
        v
A — AKATH EXECUTIVE ORCHESTRATOR
        |
        +-- Governance
        +-- Intelligence
        +-- Revenue & Business
        +-- AI Workforce
        +-- Operations
        +-- Finance & Capital
        +-- Technology & Integration
        +-- Risk / QC / PCSEV
        +-- Company Memory / Data
        +-- Business Units
```

### K responsibilities

- Set company direction and major objectives.
- Approve strategic changes and actions above defined authority boundaries.
- Approve material/high-risk financial or legal commitments as required.
- Override or stop A/system activity when necessary.
- Receive executive-level reporting rather than perform routine operations.

### A responsibilities

- Translate K-approved objectives into operating plans.
- Prioritize opportunities and tasks.
- Route work to appropriate AI/tool executors.
- Monitor execution and resource use.
- Enforce governance, risk, PCSEV, evidence, and verification rules.
- Manage business portfolio decisions within approved boundaries.
- Escalate only decisions that require K authority.

### System/AI responsibilities

- Execute assigned work within explicit permissions.
- Report evidence and failures honestly.
- Never modify K/A authority, identity, or control boundaries.
- Never infer completion from heartbeat, queue presence, persistence, or a model statement alone.

## 3. Core Divisions

AKATH consists of nine core divisions plus a cross-cutting Integration Layer.

### 01 — Governance

Authority, policy, approval boundaries, strategic controls, decision records, and executive reporting.

### 02 — Intelligence

Market research, opportunity discovery, customer/problem discovery, competitive analysis, trend monitoring, and decision intelligence.

### 03 — Revenue & Business Factory

Discovery, validation, launch, operation, measurement, scaling, optimization, and controlled shutdown of business units and revenue streams.

### 04 — AI Workforce

Capability registry, executor profiles, dynamic routing, fallback selection, performance history, and AI workforce expansion.

### 05 — Product Factory

Transform validated customer problems into services, digital products, software, media, and other commercially viable outputs.

### 06 — Operations

Task queues, scheduling, dispatch, recurring workflows, execution tracking, notifications, records, recovery, and monitoring.

### 07 — Finance & Capital

Revenue, operating costs, cash management, reserve management, growth capital, capital allocation, financial controls, and investment readiness.

### 08 — Technology & Integration

Integration Layer, APIs, connectors, identity/access, automation infrastructure, deployment surfaces, business-system integrations, observability, and reliability.

### 09 — Risk / QC / PCSEV

Risk scoring, quality control, evidence standards, verification, incident handling, emergency stop, root-cause analysis, learning, and continuous reflection.

## 4. AKATH Integration Layer

The Integration Layer is the central nervous system connecting A, AI, tools, company systems, and business channels.

```text
A
 |
v
AKATH INTEGRATION LAYER
 |
 +-- AI Connectors
 +-- Business Connectors
 +-- Company-System Connectors
 +-- Auth / Permission Control
 +-- Routing
 +-- Execution
 +-- Observation
 +-- Evidence
 +-- Verification
```

### Design rules

1. Business systems should not be hard-wired to a specific AI provider.
2. Business requests should target capabilities; the router chooses an available verified executor.
3. Executors are replaceable resources, not company dependencies.
4. Every connector has explicit capability, access, cost, reliability, quality, automation level, and permission metadata.
5. Financial actions have stricter authorization and evidence requirements than ordinary operations.
6. The Integration Layer transports/executes; it does not become the source of truth for company identity or strategic state.

### Capability-based routing

```text
TASK
 -> REQUIRED CAPABILITY
 -> AVAILABLE EXECUTORS
 -> RANK
 -> PRIMARY
 -> FALLBACK
 -> EXECUTE
 -> VERIFY
```

## 5. Revenue & Business Factory

The revenue system starts with zero investment and prioritizes the fastest credible path to real revenue.

```text
MARKET
 -> OPPORTUNITY
 -> VALIDATE
 -> ZERO-COST TEST
 -> BUILD
 -> LAUNCH
 -> SELL
 -> MEASURE
 -> SCALE / OPTIMIZE / KILL
```

### Initial revenue channels

Priority is evidence-driven, not permanently fixed. Initial candidates are:

1. AI services / productized services.
2. Digital products.
3. AI software / micro-tools.
4. Research / data / reports.
5. Content-to-revenue systems.
6. Affiliate / referral channels.
7. Creative media products and services.
8. Additional business models discovered by the opportunity engine.

### Business-unit rules

Every business starts with zero assumed market traction. A business must earn progression by evidence, including:

- Customer problem evidence.
- Offer/value evidence.
- Production feasibility.
- Distribution feasibility.
- First customer or equivalent market validation.
- Revenue evidence where revenue is the target.
- Cost and margin evidence.
- Repeatability evidence before scaling.

A business may be scaled, optimized, paused, or killed based on evidence.

## 6. AI Workforce & Autonomous Operations

AKATH uses a capability registry rather than a static list of AI brands.

Core capabilities include:

- Research
- Market intelligence
- Strategy
- Data
- Writing
- Coding
- Design
- Image
- Audio
- Video
- Marketing
- Sales operations
- Customer operations
- Automation
- Finance analysis
- Quality control

Each executor profile records:

- executor identity
- access channel
- verified capabilities
- proven task types
- speed
- quality
- reliability
- cost/usage considerations
- automation level
- permission level
- failure history
- last verified state

### Autonomous operations loop

```text
MISSION
 -> OBJECTIVE
 -> TASKS
 -> DISPATCH
 -> EXECUTE
 -> EVIDENCE
 -> QC
 -> VERIFY
 -> RESULT
 -> A REVIEW
 -> NEXT ACTION
```

### Required state separation

`APPROVED`, `QUEUED`, `DISPATCHED`, `EXECUTING`, `VERIFYING`, `COMPLETED`, `FAILED`, `BLOCKED`, `PAUSED`, and `CANCELLED` are distinct states.

Heartbeat, monitor status, persistence, and queue presence do not imply execution or completion.

## 7. Finance & Revenue-to-Capital Engine

### Economic sequence

```text
REVENUE
 -> OPERATING CASH
 -> REQUIRED COSTS
 -> SURVIVAL RESERVE
 -> GROWTH CAPITAL
 -> PROFIT SURPLUS
 -> INVESTMENT CAPITAL
 -> ASSET PORTFOLIO
```

### Initial financial principle

`Initial investment capital = ฿0`

The company first uses AI, existing tools, organic distribution, and automation opportunities to generate revenue. The first financial milestone is operating break-even: revenue sufficient to cover necessary recurring operating expenses.

### Capital buckets

- Operating Cash
- Survival Reserve
- Growth Capital
- Investment Capital
- Experimental Capital

These are target buckets, not fixed percentages. A may adjust allocation based on real cash flow, runway, opportunity, risk, liquidity, and strategic value within approved policies.

### Investment engine

After sustainable operating cash flow and adequate reserves are established, AKATH may evaluate:

- Defensive assets
- Growth assets
- Opportunistic/high-risk assets
- Strategic holdings
- Experimental allocations

Every investment requires a thesis, risk boundary, capital amount, liquidity assessment, expected outcome, review date, evidence, and authorization appropriate to the risk class.

## 8. Governance, Risk & PCSEV

### Decision classes

- **Routine:** A may execute within standing authority.
- **Material:** A prepares and escalates for required K approval.
- **High Risk:** K approval required.
- **Strategic:** K decision required.

### Risk levels

- LOW → autonomous within policy
- MEDIUM → A review/control
- HIGH → K approval
- CRITICAL → block and escalate

### PCSEV doctrine

```text
P — PROBLEM
C — CAUSE
S — SOLUTION
E — EXECUTE
E — EVIDENCE
V — VERIFY
```

Post-verification learning:

`LEARN → UPDATE → STANDARDIZE`

### Evidence hierarchy

```text
REAL-WORLD EVIDENCE
        ↑
VERIFIED SYSTEM RESULT
        ↑
EXECUTION RECORD
        ↑
AI REPORT
        ↑
PLAN / CLAIM
```

A claim is never promoted to completed status solely because an AI reported success.

### Emergency control

Critical incidents must support:

`STOP → PRESERVE → EVIDENCE → ESCALATE → ROOT CAUSE → RECOVER → VERIFY`

## 9. Company Memory & Data Architecture

AKATH memory is divided into:

1. Identity
2. Mission
3. Knowledge
4. Current state
5. Tasks
6. Evidence
7. Learning

Canonical entity types must support durable IDs, including:

`COMPANY-ID`, `BUSINESS-ID`, `PRODUCT-ID`, `TASK-ID`, `JOB-ID`, `AI-ID`, `ASSET-ID`, `TRANSACTION-ID`, `EVIDENCE-ID`, and `DECISION-ID`.

### Source-of-truth hierarchy

```text
K DECISION
  ↑
A MASTER BRAIN
  ↑
VERIFIED COMPANY STATE
  ↑
VERIFIED EVIDENCE
  ↑
SYSTEM RECORDS
  ↑
AI REPORTS
  ↑
UNVERIFIED INPUT
```

### Cross-runtime rehydration

A new AI/runtime must be able to load:

- AKATH identity
- authority model
- current company state
- active tasks
- decisions
- knowledge needed for current work
- relevant evidence
- operational rules

Then perform identity, integrity, and conflict checks before acting as A.

### Memory isolation

Business data, finance data, operational data, and core company data remain separable so that failure in one business does not corrupt company-wide state.

## 10. Company Lifecycle & Self-Expansion Engine

The company operates a repeated loop:

```text
OBSERVE MARKET
 -> SCORE OPPORTUNITY
 -> A DECISION
 -> TEST / BUILD / REJECT
 -> VALIDATE
 -> REVENUE
 -> MEASURE
 -> SCALE / OPTIMIZE / KILL
 -> CAPTURE LESSON
 -> NEXT CYCLE
```

### Business replication

A proven business creates reusable patterns for:

- process
- workflow
- AI allocation
- sales channels
- KPI model
- cost model
- QC model

The next business inherits the proven operating pattern, but must independently validate its own market.

### AI and tool expansion

New capability request:

`NEED → CHECK EXISTING → FIND/ADD EXECUTOR → TEST → VERIFY → REGISTER → ROUTE`

Infrastructure should not expand merely because it is interesting; expansion must have demonstrated business, reliability, or operating value.

## 11. K Minimum-Work Operating Model

K's intended operating role is exception-based governance.

```text
K TARGET / APPROVAL
        ↓
A STRATEGY + PRIORITIES
        ↓
AI + SYSTEM EXECUTION
        ↓
PCSEV / EVIDENCE / VERIFY
        ↓
A EXECUTIVE REVIEW
        ↓
K EXECUTIVE REPORT
```

K should not routinely:

- dispatch individual tasks
- manually coordinate every AI
- inspect every operational log
- repair every workflow step
- repeatedly provide context that the company memory already contains

K remains responsible for decisions that exceed A's authority boundary.

## 12. Legacy / AERIS Treatment

AERIS is not part of the AKATH target company structure.

AERIS-era systems, code, dashboards, blueprints, and records are classified as **Legacy Reference Material** during the transition. No item is considered migrated merely because it exists in legacy storage.

Potentially useful lessons may be extracted only after PCSEV/evidence review and then rewritten into AKATH-native specifications.

The target architecture must not depend on AERIS naming, AERIS-specific folder taxonomy, AERIS company assumptions, or AERIS runtime endpoints.

## 13. Explicit Non-Claims

This specification does not claim that:

- AKATH runtime has already been built.
- Every connector already exists.
- Every AI executor is currently reachable.
- Every business channel is automated.
- Autonomous financial execution is enabled.
- Revenue is currently being generated by the new AKATH structure.
- Legacy AERIS infrastructure has been safely migrated.
- Any task is complete without evidence and verification.

## 14. Acceptance Criteria for the Architecture

The AKATH architecture is considered implementation-ready when:

1. Identity and authority are defined without ambiguity.
2. The Master Brain and company memory model are defined.
3. Integration Layer boundaries are defined.
4. Capability-based AI routing is defined.
5. Revenue-first business lifecycle is defined.
6. Financial control and investment gates are defined.
7. PCSEV and evidence standards are mandatory across critical workflows.
8. K approval boundaries are explicit.
9. Legacy AERIS dependencies are identified and isolated.
10. Implementation can proceed in stages without requiring K to manually operate each workflow.

## 15. Implementation Direction After Spec Review

Implementation should proceed only after this written specification is reviewed and accepted as the target architecture.

Initial implementation priority:

1. AKATH canonical identity and company state.
2. Master Brain / memory / durable IDs.
3. Integration Layer foundation.
4. AI Capability Registry and routing.
5. Revenue Factory and first zero-cost revenue experiments.
6. Operations / queue / evidence / verification.
7. Financial Control.
8. Governance / Risk / PCSEV enforcement.
9. Dashboard and executive interface.
10. Business scaling and asset/investment engine.

## 16. Success Definition

AKATH succeeds when:

- K can set objectives without performing routine operations.
- A can orchestrate company work within explicit authority.
- AI and tools can be swapped or expanded without redesigning the whole company.
- Every important execution has evidence and verification.
- The company can create revenue from zero investment.
- Revenue reaches and sustains operating break-even.
- Profits can fund business expansion.
- Surplus capital can later feed a controlled asset/investment portfolio.
- Business creation, operation, learning, and expansion form a repeatable company-level loop.

---

**Specification state:** Ready for user review before implementation planning.
