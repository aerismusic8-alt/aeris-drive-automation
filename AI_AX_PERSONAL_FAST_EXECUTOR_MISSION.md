# AX Personal Fast Executor Mission v1.0

## Objective
Create and establish a dedicated AI utility lane for AX using the already-approved account/email, without interrupting the 6-AI Revenue Network.

## Role
AX Personal Fast Executor is a non-revenue utility worker for urgent tasks such as dashboard/UI work, coding, reports, research, internal tools, QA support, and automation utilities.

## Architecture
- Revenue AI Network remains the priority production lane.
- Personal Fast Executor is a parallel utility lane.
- Dashboard is read-only against execution state and must not become an execution dependency.
- Never expose or store passwords, API keys, OTPs, or other secrets in repository state.

## Required lifecycle
ACCOUNT_READY -> AI_READY -> BLUEPRINT_DELIVERED -> CONNECTED -> E2E_EXECUTED -> VERIFIED -> READY

## First Mission
Use the existing AX Command Center Dashboard as the first real-world task. Improve only dashboard/UI scope unless AX explicitly dispatches another utility task.

## Verification Gate
An AI is not considered connected merely because an account exists or a Blueprint was delivered. Connection requires evidence of task dispatch, response, successful execution, and verification.

## Failure Handling
AX must Diagnose -> Retry -> Fallback -> Verify before requesting K intervention. Ask K only for authentication, consent, permissions, billing, or other actions that inherently require the account owner.

## Priority
This lane must not interrupt or modify the 6-AI Revenue Network execution path. Revenue work wins any resource conflict.
