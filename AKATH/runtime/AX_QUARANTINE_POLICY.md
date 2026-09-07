# AX Quarantine / Trash Flow V1

## Scope
Applies to every autonomous task, artifact, adapter result, generated file, workflow result, and execution result handled by AKATH/AX.

## Rule
Anything that is detected as invalid, failed validation, malformed, unsafe to continue with, contradictory to the task contract, or otherwise not eligible for active execution MUST be quarantined before it can re-enter an active queue.

## Quarantine is not deletion
Quarantine preserves the original item for diagnosis and recovery. Nothing is permanently deleted by this policy.

## Required quarantine record
Each quarantined item must retain:
- task/request ID
- source/provider/worker
- timestamp
- original location or queue
- validation status
- failure reason/error class
- verification status
- retry count if known
- quarantine location

## Re-entry rule
A quarantined item is inactive. It MUST NOT be automatically re-executed until it passes validation again or is explicitly repaired and re-queued by an authorized execution path.

## Lifecycle
ACTIVE -> VALIDATING -> VERIFIED -> EXECUTABLE
ACTIVE -> VALIDATING -> INVALID/FAILED -> QUARANTINED
QUARANTINED -> REPAIRED -> VALIDATING -> VERIFIED -> EXECUTABLE
QUARANTINED -> RETAINED

## Safety
- Never mark a quarantined item PASS.
- Never overwrite evidence needed to diagnose the failure.
- Never silently discard or permanently delete failed work.
- Quarantine is applied before retry when the current artifact/result is known invalid; retries operate on a repaired or newly generated candidate, not the invalid active item.
