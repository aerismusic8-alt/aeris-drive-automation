# PC1 / PC2 INDEPENDENT BRAIN-CONTROL ARCHITECTURE

## Canonical node architecture

Every AERIS execution node follows the same architecture:

PC → Runtime → Brain → Control → Vision / OS / Browser → Evidence → Verify → Write-back

The node is autonomous after Runtime startup. ChatGPT/AX-GPT is not the runtime controller and Desktop Commander is not authoritative.

## Authority and responsibilities

- K = human final authority and approval boundary.
- AX = executive/orchestration layer; creates, upgrades, audits, and synchronizes Brain architecture and knowledge.
- A MASTER BRAIN = durable knowledge, procedures, lessons, recovery knowledge, and verified experience.
- Runtime = persistent local process that keeps the node alive, restores state, emits heartbeat, and launches Brain/Control.
- Brain = local decision layer. It observes canonical state + current evidence, determines the next valid action, diagnoses failures, selects recovery, and issues a bounded directive to Control.
- Control = execution layer. It does not invent goals. It receives Brain directives and performs the authorized OS/browser/vision actions.
- Vision = desktop/browser observation layer and evidence source.
- Evidence = persisted proof of what actually happened.
- Verify = independent state/effect check; no success flag alone is accepted.
- Write-back = durable state/lesson update used by Brain and A MASTER BRAIN.

## PC1

- nodeId: PC1-MAIN
- machine: DESKTOP-RGK6JKB
- role: PRIMARY
- local Runtime: required
- local Brain: required
- local Control: required
- Desktop Vision: required
- Browser/OS execution: local
- Evidence + Verify + Write-back: local and canonical-sync capable

## PC2

- nodeId: PC2-NIGHT
- machine: DESKTOP-M9M4818
- role: SECONDARY
- local Runtime: required
- local Brain: required
- local Control: required
- Desktop Vision: required
- Browser/OS execution: local
- Evidence + Verify + Write-back: local and canonical-sync capable

PC1 and PC2 must remain independently executable. One node being offline must not stop the other node's local Runtime → Brain → Control loop.

## Brain → Control contract

Brain may issue only an explicit, bounded directive containing:

1. current canonical task
2. current node
3. observed state/evidence references
4. selected action
5. allowed executor/capability
6. verification condition
7. recovery condition
8. attempt/budget limits

Control executes the directive and returns execution evidence. If evidence does not satisfy the verification condition, Brain must classify the failure and choose recovery, retry, or the next candidate.

## Autonomous recovery loop

INSPECT → RESEARCH/KNOWLEDGE → ROOT CAUSE → FIX/RECOVER → RUN → EVIDENCE → VERIFY → WRITE-BACK → NEXT

The loop continues after a failure. A failure is not a completion state.

For bounded offer work:

DISCOVER → READ RULES → FEASIBILITY → START → EXECUTE → VERIFY EFFECT/REWARD → WRITE-BACK → NEXT OFFER

An offer that cannot legitimately be completed is persisted as BLOCKED/SKIPPED with the reason and evidence, then the Brain selects the next eligible offer. No fabricated completion, reward, answer, or anti-fraud bypass is permitted.

## Evidence gate

PASS requires current node-specific evidence and independent verification.

The following are not sufficient by themselves:

- a process being started
- a browser page being open
- a generic success message
- a stale screenshot
- a control-state flag
- a Git commit

Connection loss is not task completion.

## Transport

Desktop Commander is an optional transport/adapter only. The canonical control plane is the node's local Runtime → Brain → Control architecture.

## Recovery and synchronization

On reconnect:

REGISTER → HEARTBEAT → READY → RECONCILE CANONICAL STATE → DISPATCH → ACK → EXECUTE → RESULT → VERIFY → WRITE-BACK

The node must reconcile its last local state with canonical state before performing another side-effecting action.

## Invalid legacy identity

DESKTOP-O0AUKHG is not a current AERIS node.
