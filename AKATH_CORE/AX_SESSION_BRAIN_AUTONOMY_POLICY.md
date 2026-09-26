# AX Session Activation and Brain Autonomy Policy

## Locked rule

AX is activated by K through a ChatGPT session. AX is not a required runtime dependency and must not be turned into a permanent watchdog.

While K is in session, AX may inspect evidence and make authorized system-level repairs/upgrades:
- Brain logic and recovery;
- Control lifecycle;
- Vision and evidence;
- Verify;
- Resource Governance;
- knowledge and architecture.

AX does not perform routine desktop/Offer execution as a substitute for Brain.

After the session ends, the node must continue through:

Runtime → Brain → Control → Vision/OS/Browser → Evidence → Verify → Write-back

Brain owns autonomous decision-making and recovery.

If Brain cannot recover a problem within its bounded strategies, it must write an explicit escalation record:

ESCALATE_TO_AX

The escalation must include:
- failure classification;
- current evidence;
- attempted recovery strategies;
- attempt count;
- resource state;
- missing capability/knowledge;
- recommended next repair target.

The next AX session can consume this record and repair the underlying weakness.

## Resource rule

Resource health is a mandatory decision input.

Each node must classify resource state as:
HEALTHY
DEGRADED
RESOURCE_PRESSURE
CRITICAL

Resource pressure must cause Brain to reduce or defer expensive work, clean safe stale processes/windows, or stop non-essential execution.

A task is not a healthy success if it leaves the node in uncontrolled resource pressure.

## Autonomous transition

PHASE_1_AX_REPAIR_UPGRADE:
AX improves Brain and supporting systems during K sessions.

PHASE_2_BRAIN_AUTONOMOUS:
Brain runs the verified system without AX being continuously present.

The transition requires evidence that:
Runtime, Brain, Control, Vision, Evidence, Verify, Write-back, recovery, and resource governance are functioning.

No recurring ChatGPT timer is required for normal operation.

## Tool selection rule

Tool and program selection is a Brain responsibility and is part of the execution architecture. Brain must choose by:
Capability + Resource Cost + Reliability + Integration + Recovery.

Selection order:
1. Reuse an existing approved session/process when sufficient.
2. Prefer DOM/API/Playwright for browser state and structured web evidence when sufficient.
3. Prefer lightweight Windows-native automation for desktop/window/input work.
4. Use Desktop Vision/OCR when desktop visual state is required.
5. Use a VLM only when DOM/OCR/other evidence is insufficient for the required semantic decision.

Before starting or installing a tool, Brain must inspect resource pressure and avoid duplicate browsers/processes. Under RESOURCE_PRESSURE, reduce expensive capture/OCR/VLM work and defer non-essential launches. Under CRITICAL, enter recovery-only mode and do not start or install new heavy tools until resource health is restored.

New tools must be benchmarked for resource cost, reliability, integration, and recovery behavior before becoming an approved execution path. A more powerful tool is not automatically a better tool.

Tool selection must be recorded in current Brain evidence/state with selected tool, reason, resource state, and fallback.