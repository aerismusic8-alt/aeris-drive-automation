# PC1 MeshCentral AX Remote Adapter

Purpose: give AX a remote transport path to PC1 without bypassing the canonical Brain/Control authority.

Canonical path:
AX -> MeshCentral Adapter -> PC1 Brain -> PC1 Control -> local Desktop/Vision -> local Evidence -> Verifier.

The adapter is transport only. It does not select intents and it cannot mark a job VERIFIED.

## Required host-side configuration

The adapter runs on the AX/control host and invokes MeshCtrl. MeshCtrl supports RunCommand against a remote device and requires MeshCentral authentication. Use a dedicated MeshCentral account with only the required PC1 device-group permissions.

Environment variables:
- AKATH_MESHCTRL_JS = full path to meshctrl.js
- AKATH_MESHCTRL_URL = MeshCentral websocket URL, for example wss://server/
- AKATH_MESHCTRL_LOGINUSER = dedicated MeshCentral username
- AKATH_MESHCTRL_KEYFILE = local login-key file, preferred
- AKATH_MESHCTRL_LOGINPASS = password alternative; do not commit it

Do not put credentials, login keys, or passwords in Git.

## First proof

Run:

powershell -ExecutionPolicy Bypass -File .\AX_PC_CONTROL\pc1-meshcentral-ax-dispatch.ps1 -Action Health

PASS requires:
- MeshCentral authentication succeeds.
- PC1 is found by computer name DESKTOP-RGK6JKB.
- remote hostname returns DESKTOP-RGK6JKB.

Then dispatch a harmless Brain intent:

powershell -ExecutionPolicy Bypass -File .\AX_PC_CONTROL\pc1-meshcentral-ax-dispatch.ps1 -Action DispatchIntent -Intent NODE_HEALTH_CHECK -JobId AX-MESH-PROOF-001

The remote command only writes an intent file into the PC1 Brain pending queue. PC1 Brain then decides and PC1 Control executes it locally.

This keeps AX out of direct execution authority.

## Security boundary

Allowed intents are limited to the existing PC1 Brain intent allowlist:
NODE_HEALTH_CHECK
SYSTEM_DIAGNOSTIC
CLOSE_STALE_TERMINAL
CAPTURE_AND_REVERIFY
RESTART_OWNED_RUNTIME
INCIDENT_LOCAL_DIAGNOSE

Arbitrary remote shell commands are not accepted by the adapter.
