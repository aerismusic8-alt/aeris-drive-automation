# AX Mission Memory Protocol V1

## Purpose

The AX Mission Ledger is the durable source of truth for K-assigned work. Chat sessions, AI workers, PCs, and dashboards are interfaces or execution surfaces; they are not the authoritative mission record.

## Mission identity

Every explicitly assigned task receives one stable `missionId`. The ID remains unchanged when K follows the task from another chat, channel, PC, worker, or session.

## Required record

A mission retains:

- original objective and deadline
- priority
- current lifecycle status
- every participating channel reference
- latest conversation/update as `lastConversation`
- event history
- worker allocation
- output references
- verification result
- evidence references
- AX certification state
- business/product/revenue extension assessment

## Event rule

Each update is an immutable event with a deterministic `eventId`. Replaying the same event is a no-op. Ordinary conversation does not create a mission; only explicit task-intake events or an existing `missionId` may mutate mission state.

## Cross-channel rule

When K asks for a status from another channel, AX resolves the existing `missionId` from the durable ledger first. The latest event becomes the current conversation projection while the complete event history remains available.

## No-loss rule

A mission is never deleted merely because it is completed, failed, old, or no longer active. Lifecycle state changes; history remains searchable. `ARCHIVED` means inactive, not forgotten.

## Recovery rule

After process, runner, PC, or session restart, AX must reload the ledger and recover the same Mission ID, latest state, latest conversation, event history, evidence references, and certification state.

## Security rule

Credentials and authentication material must never be persisted. Obvious secret-bearing fields are redacted before mission events are written.

## Success rule

`NOT VERIFIED ≠ SUCCESS`. Mission delivery requires Execute → Output → Verify → Evidence → AX Certification.

## Business rule

Every mission receives a business-extension assessment. Where appropriate, the completed capability must be evaluated as a reusable product, service, internal platform, or revenue channel.

## Operational query

The minimum status query is:

`Mission ID → Objective → Status → Latest Update → Worker → Output → Verification → Evidence → AX Certification → Next Action → Business Extension`
