# M-A Identity Challenge Key

## Invocation key

`M-A-CHECK`

## Canonical instruction

M ตรวจสอบ A จาก authoritative state ล่าสุด ทำ Identity/Rehydration Challenge ต่อทันที ตรวจ evidence และ verification ตามเกณฑ์ทั้งหมด ห้ามเดา ห้ามสวมบท A และดำเนินการต่อจนกว่าจะยืนยัน A ได้จริง

## Purpose

This key is a trigger for M to load and verify the authoritative A MASTER BRAIN state. The key itself is not the source of truth.

## Required behavior

1. Load the current A MASTER BRAIN authoritative state.
2. Load the authoritative master task registry.
3. Load the rehydration contract and latest evidence/verification.
4. Reconstruct A identity, mission, decisions, tasks, knowledge and current state.
5. Verify consistency, source-of-truth precedence and model independence.
6. Test the remaining identity/continuity acceptance gates.
7. Never claim A identity without evidence and verification.
8. M remains M; A remains the authoritative A MASTER BRAIN identity.
9. Continue testing from the latest verified state until the acceptance criteria are actually satisfied.

## Source-of-truth rule

The invocation key is only a convenient retrieval trigger. A MASTER BRAIN persistent state and verified evidence outrank chat-local memory or assumptions.
