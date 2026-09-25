# AKATH Management Architecture

## Purpose

The AERIS management structure governs both autonomous execution and continuous improvement. Management is separate from local execution.

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

K remains final authority. AX manages the system and develops/upgrades the Brain. A MASTER BRAIN stores durable knowledge and experience; it does not independently redefine current authority or verified operational state.

## Management layers

### 1. K — Final Authority
- approves strategic changes and sensitive decisions;
- defines or approves top-level goals;
- may stop or override the system.

### 2. AX Executive — Management / Orchestration
- converts approved goals into managed objectives;
- prioritizes work across PC1 and PC2;
- creates and upgrades Brain capabilities;
- monitors health, progress, failures, resource use, and evidence quality;
- coordinates research and knowledge upgrades;
- does not directly perform routine desktop actions.

### 3. A MASTER BRAIN — Durable Intelligence
- stores verified procedures, lessons, failure patterns, recovery methods, and architecture knowledge;
- feeds knowledge to AX and node Brains;
- receives verified write-backs;
- continuously improves from evidence;
- never treats an unverified observation as a lesson.

### 4. Node Brain — Local Management
Each node has its own Brain:
- PC1 Brain → manages PC1 Control;
- PC2 Brain → manages PC2 Control.

Node Brain responsibilities:
- inspect current state;
- choose the next bounded action;
- diagnose failures;
- select recovery;
- enforce attempt/resource/time limits;
- request research when knowledge is insufficient;
- verify that Control's result satisfies the directive.

### 5. Node Control — Execution Management
Control:
- receives Brain directives;
- manages OS/browser/application execution;
- coordinates Vision with execution;
- closes stale/unused windows where permitted;
- stops unsafe or unsupported actions;
- returns evidence;
- never changes the objective by itself.

## Management loop

PLAN → DISPATCH → OBSERVE → DECIDE → EXECUTE → EVIDENCE → VERIFY → WRITE-BACK → REVIEW → NEXT

Failure loop:

FAILURE → CLASSIFY → ROOT CAUSE → RESEARCH/KNOWLEDGE → RECOVER/FIX → RETEST → VERIFY → WRITE-BACK

The system must continue after recoverable failures. Repeated failure causes escalation to the next recovery strategy or next eligible task.

## Cross-node management

PC1 and PC2 are independent execution nodes.

AX manages them as separate workers:
- PC1-MAIN = PRIMARY execution node;
- PC2-NIGHT = SECONDARY execution node.

Shared knowledge does not merge local execution state.

A node going offline must not stop the other node. On reconnect, the node reconciles canonical state before side-effecting execution.

## Resource governance

Management continuously monitors:
- CPU;
- RAM;
- disk;
- browser/process count;
- Vision frequency;
- queue length;
- stale state;
- error rate.

When resources degrade, Brain reduces observation/execution frequency, closes unnecessary processes/windows where safe, or defers work. Resource pressure must not be hidden as success.

## Evidence governance

Management requires:

OBSERVATION → ACTION → EFFECT → VERIFICATION

A process start, UI presence, generic success text, stale screenshot, or state flag is not completion evidence by itself.

## Current node architecture

PC1:
PC1 → Runtime → Brain → Control → Vision/OS/Browser → Evidence → Verify → Write-back

PC2:
PC2 → Runtime → Brain → Control → Vision/OS/Browser → Evidence → Verify → Write-back

Both are governed by the same management principles.

## State authority

Current operational truth comes from Runtime + canonical registry + current evidence + verification.

ChatGPT conversation context is not authoritative runtime state.
