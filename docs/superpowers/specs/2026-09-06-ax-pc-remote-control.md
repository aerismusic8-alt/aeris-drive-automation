# AX PC Remote Control & Terminal v1 — Design Specification

**Status:** APPROVED FOR IMPLEMENTATION
**Date:** 2026-09-06
**Authority:** K (Final Authority)

## Goal

Give AX reliable, remotely reachable control of PC1 and PC2 from any location/time through outbound authenticated node agents, while preserving auditability, least-privilege boundaries, and a terminal capability for approved administrative work.

## Current Problem

GitHub can accept `workflow_dispatch`, but execution can stop at the self-hosted runner gate when the required PC runner is offline, stopped, busy, or misconfigured. The existing `AX_NODE_RUNNER.ps1` is a polling node runner, but it does not provide a general local administrative control plane.

## Architecture

`AX Control Runtime -> Secure Node Gateway -> PC1/PC2 AX Node Agent -> Local execution layer`

PC agents make outbound HTTPS connections only. No public inbound RDP/WinRM/SMB port is required. Each node has a unique credential, node identity, heartbeat, command queue, execution result, and audit trail.

## Node Roles

- **PC1:** primary autonomous executor.
- **PC2:** secondary/coding executor and failover target.
- **AX:** controller; can inspect, diagnose, dispatch, recover, and verify.
- **K:** final authority for architecture, permissions, spending, and high-risk operations.

## Terminal

The terminal is a controlled remote execution surface exposed to AX through the node agent. It must:

1. authenticate the node and command;
2. assign a command ID and correlation/task ID;
3. record command, target, start/end time, exit code, stdout/stderr and verification status;
4. enforce an execution policy before running commands;
5. return machine-readable results;
6. support timeouts and cancellation where possible;
7. never return secrets or credential files as normal command output;
8. default to non-financial execution.

The implementation must not expose an unauthenticated public shell.

## Administrative Control

The node service may run with the Windows privileges required for the approved AKATH maintenance operations. Administrative capability is local to the node service; the Internet-facing gateway must not expose Windows administrator credentials.

Initial bootstrap requires a one-time local installation/configuration on each PC. After bootstrap, the node should start automatically with Windows and maintain its heartbeat without K manually starting a runner.

## Required Operations

- node health and identity
- Windows service inspection/start/stop/restart
- GitHub Actions runner inspection/recovery
- process inspection
- Task Scheduler inspection/control
- Git/GitHub repository operations required by AKATH
- PowerShell/Python execution through the controlled terminal
- log collection
- restart/recovery workflows
- post-action verification

## Safety Boundaries

- No public inbound administrative ports required.
- No plaintext credentials in repository files.
- Per-node secrets stored locally with restrictive ACLs.
- Every remote command is authenticated and audited.
- Financial/live trading execution remains disabled by default.
- Destructive or high-impact operations require an explicit policy gate.
- AX must report FACT / INFERENCE / PLAN / EXECUTED RESULT separately.
- A failed verification stops the execution chain rather than being reported as success.

## Recovery Flow

1. AX detects a blocked GitHub job.
2. AX queries PC1 health.
3. If PC1 is unhealthy, AX diagnoses and attempts policy-approved recovery.
4. AX verifies PC1 runner availability.
5. If PC1 cannot recover, AX checks PC2.
6. AX dispatches/fails over according to the execution policy.
7. AX verifies the complete path: dispatch -> runner pickup -> execution -> state/brain rehydration -> result -> audit evidence.

## Acceptance Criteria

The system is not complete until all of these are demonstrated on real PC nodes:

- PC1 and PC2 can independently authenticate to the gateway.
- Both nodes report ONLINE heartbeats.
- AX can inspect node health remotely.
- AX can inspect the GitHub runner service remotely.
- AX can execute a harmless terminal probe and receive verified output.
- AX can restart the runner service when policy permits and verify it becomes available.
- A GitHub `workflow_dispatch` job is actually picked up by a self-hosted runner.
- PC1 failure/failover to PC2 is exercised or a deterministic failover test proves the path.
- All actions produce audit evidence.
- No public inbound admin port is required.
