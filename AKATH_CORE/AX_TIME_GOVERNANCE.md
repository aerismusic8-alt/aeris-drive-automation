# AX Time Governance

Every canonical job must declare:
- task_id
- objective
- started_at (trusted timestamp)
- deadline_at
- milestones
- completion criteria
- evidence references
- verification status
- completed_at

Required status values:
ON_TRACK, AT_RISK, OVERDUE, BLOCKED, DONE

When deadline_at is exceeded:
1. mark OVERDUE;
2. record the trusted current time;
3. identify the actual cause;
4. apply a corrective action;
5. continue execution or escalate;
6. only revise the deadline when a concrete cause and revised plan are recorded.

A late task is not made successful by changing its deadline. Time variance remains part of its evidence.
