# AKATH Management Architecture

## Purpose

The AERIS management structure separates system development from autonomous node execution. AX is the architect/supervisor and Brain is the local autonomous operator.

## Authority hierarchy

K
→ AX Executive Management
→ A MASTER BRAIN / Knowledge
→ Node Brain
→ Node Control
→ Vision / OS / Browser
→ Evidence
→ Verify
→ Write-back

K remains final authority. AX manages the system and develops/upgrades Brain. A MASTER BRAIN stores verified durable knowledge and experience; it never independently redefines authority or current verified operational state.

## AX session model — LOCKED SYSTEM RULE

AX is **session-activated by K**. AX does not need to run continuously, does not need a recurring ChatGPT heartbeat, and must not be made a required runtime dependency for normal node execution.

When K opens an AX session, AX may:
- inspect current canonical state and evidence;
- diagnose system weaknesses;
- repair or upgrade Brain, Control, Vision, Verify, Resource Governance, and supporting architecture;
- research missing knowledge;
- test and verify changes;
- write verified lessons to A MASTER BRAIN;
- prepare the node to resume autonomous operation.

AX must not become a routine desktop executor or permanent watchdog.

When K closes the session:
- Runtime, Brain, Control, Vision, Verify, and Write-back continue independently;
- no normal operation may depend on AX remaining online;
- recoverable failures are handled by Node Brain;
- failures that exceed Brain capability are recorded as `ESCALATE_TO_AX` with evidence and await the next K→AX session.

There is no requirement to create a recurring AX timer merely to simulate supervision.

## Management layers

### 1. K — Final Authority
- approves strategic changes and sensitive decisions;
- defines or approves top-level goals;
- may stop or override the system.

### 2. AX Executive — Architecture / Repair / Upgrade / Audit
- converts approved goals into managed objectives;
- diagnoses system weaknesses;
- creates and upgrades Brain capabilities;
- repairs architecture and implementation when K authorizes it;
- researches missing knowledge;
- audits evidence, verification, recovery, and resource behavior;
- does not perform routine Offer/desktop actions as a substitute for Brain.

### 3. A MASTER BRAIN — Durable Intelligence
- stores verified procedures, lessons, failure patterns, recovery methods, resource rules, and architecture knowledge;
- feeds knowledge to AX and node Brains;
- receives only verified write-backs;
- never treats an unverified observation as a lesson.

### 4. Node Brain — Autonomous Local Management
Each node has its own Brain:
- PC1 Brain → manages PC1 Control;
- PC2 Brain → manages PC2 Control.

Node Brain responsibilities:
- inspect current state;
- choose the next bounded action;
- diagnose failures;
- select recovery;
- enforce attempt/resource/time limits;
- request/record missing knowledge;
- verify Control results;
- escalate unresolved problems as `ESCALATE_TO_AX`.

### 5. Node Control — Execution
Control:
- receives Brain directives;
- manages OS/browser/application execution;
- coordinates Vision with execution;
- manages process/window lifecycle;
- closes stale/unused windows where safe;
- stops unsupported or unsafe actions;
- returns evidence;
- never changes the objective by itself.

## Autonomous management loop

PLAN → DISPATCH → OBSERVE → DECIDE → EXECUTE → EVIDENCE → VERIFY → WRITE-BACK → REVIEW → NEXT

Failure loop:

FAILURE → CLASSIFY → ROOT CAUSE → RECOVERY/FIX → RETEST → VERIFY → WRITE-BACK

If Brain lacks the knowledge or capability to recover:

FAILURE → CLASSIFY → EVIDENCE → ESCALATE_TO_AX → WAIT_FOR_NEXT_AX_SESSION

Repeated failure must not become an infinite blind retry loop.

## Resource governance

Resource health is a first-class execution constraint, not an afterthought.

Every node must consider:
- CPU;
- RAM and memory pressure;
- disk/free space;
- browser count and browser memory;
- process/window count;
- Vision capture frequency;
- OCR/VLM load;
- queue length;
- error rate;
- response/heartbeat latency.

Brain must use resource state when deciding whether to start, continue, defer, or stop work.

Resource policy:
- HEALTHY → normal operation;
- DEGRADED → reduce observation/verification frequency where safe;
- RESOURCE_PRESSURE → defer new heavy work, close safe stale processes/windows, reduce Vision/OCR load;
- CRITICAL → preserve Runtime/Brain/Control/Verify, stop non-essential execution, recover resources first.

A task is not considered successful if it completes while causing uncontrolled resource degradation.

## Offer feasibility gate

Before starting a new Offer, Brain must evaluate both task requirements and resource feasibility.

DISCOVER → READ RULES → UNDERSTAND REQUIREMENTS → CHECK COMPATIBILITY → CHECK RESOURCE FEASIBILITY → START

Resource feasibility must consider expected RAM/CPU/browser/Vision cost and current node health.

High resource cost is a reason to defer or select another eligible task; it is not a reason to overload the machine.

## Evidence governance

Management requires:

OBSERVATION → ACTION → EFFECT → VERIFICATION

A process start, UI presence, generic success text, stale screenshot, or state flag is not completion evidence by itself.

Reward completion must remain distinct from task start and milestone execution:

ACTION → MILESTONE EVIDENCE → PARTNER/REWARD VERIFICATION → REWARD EVIDENCE → WRITE-BACK

## Cross-node management

PC1 and PC2 are independent execution nodes.

AX manages them as separate workers:
- PC1-MAIN = PRIMARY execution node;
- PC2-NIGHT = SECONDARY execution node.

Shared knowledge does not merge local execution state.

A node going offline must not stop the other node. On reconnect, the node reconciles canonical state before side-effecting execution.

## Current node architecture

PC1:
PC1 → Runtime → Brain → Control → Vision/OS/Browser → Evidence → Verify → Write-back

PC2:
PC2 → Runtime → Brain → Control → Vision/OS/Browser → Evidence → Verify → Write-back

Both are governed by the same management principles.

## State authority

Current operational truth comes from Runtime + canonical registry + current evidence + verification.

ChatGPT conversation context is not authoritative runtime state.

## Operational transition

Until Brain passes the autonomous verification gate, the system is in:

PHASE 1 — AX REPAIR/UPGRADE MODE

After Brain passes the gate:

PHASE 2 — BRAIN AUTONOMOUS MODE

AX may still improve the system whenever K opens a session, but AX is not required for normal execution.
