# AX PC Control

Remote execution subsystem for PC1 and PC2.

## Purpose

Provide AX with an authenticated control path to managed Windows execution nodes without exposing Windows administration ports directly to the Internet.

## Components

- `AX_PC_NODE.ps1` — Windows node agent / terminal bridge.
- `AX_PC_NODE_CONFIG.example.json` — node configuration template.
- `AX_PC_TERMINAL_PROTOCOL.md` — command/result contract.

## Security model

The node initiates outbound HTTPS to the AX Control Runtime. No inbound RDP, WinRM, SMB, or arbitrary admin port is required. Authentication uses the existing `AX_PC_PULL_SECRET` transport secret, while command authorization is enforced locally by an explicit allowlist.

Administrative operations are supported through controlled PowerShell commands. The agent must run as a Windows service account with only the privileges required by the approved operation set. Full unrestricted remote shell is intentionally not exposed.

## Execution lifecycle

`AX → Control Runtime → PC node pull → authorize → execute → result → ACK → verify`

Every command receives a command ID and returns exit code, stdout/stderr, duration, node identity, and verification metadata.

## Bootstrap

The repository includes the node implementation and installer scripts, but the first installation on PC1/PC2 requires execution on the target Windows machine. Do not paste secrets into the repository.
