# AX Provisioning Status

## Verified 2026-09-03

- Cloudflare Worker `ax-control-runtime`: deployed and ONLINE.
- Execution mode: `FREE_ONLY`.
- Live financial execution: disabled.
- Queue: `ax-execution-events`.
- PC self-hosted runner: verified executing on Windows/X64 (`DESKTOP-RGK6JKB`).
- Automated acceptance workflow: configured for `workflow_dispatch` and push to `main`.

## Current gate

The production acceptance gate remains **NOT PASS** until the deployed Worker reports:

- `mobileIngressAuthConfigured=true`
- `pcPullAuthConfigured=true`

The Worker currently reports both values as unconfigured. The required secrets are:

- `AX_MOBILE_INGRESS_SECRET`
- `AX_PC_PULL_SECRET`

These values must be provisioned directly as Cloudflare Worker secrets. Never commit, print, log, or paste the secret values into Git, chat, issues, workflow YAML, or documentation.

Provisioning automation and verification are in:

- `AX_CONTROL_HUB/AX_SECRET_PROVISION.ps1`
- `AX_CONTROL_HUB/AX_SECRET_PROVISIONING_RUNBOOK.md`
- `.github/workflows/ax-control-runtime-acceptance.yml`

The acceptance workflow is intentionally fail-closed: missing or short credentials fail before Mobile/PC E2E is accepted.
