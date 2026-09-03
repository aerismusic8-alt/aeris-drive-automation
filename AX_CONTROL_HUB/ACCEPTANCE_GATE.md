# AX Control Runtime Acceptance Gate

## Current gate

The acceptance gate is intentionally fail-closed.

Required deployed Worker health:

- `status=ONLINE`
- `mode=FREE_ONLY`
- `liveFinancialExecution=false`
- `mobileIngressAuthConfigured=true`
- `pcPullAuthConfigured=true`
- `gatewayInbox=AX_GATEWAY_INBOX`

## Required one-time provisioning

Provision these as Cloudflare Worker secrets on `ax-control-runtime`:

- `AX_MOBILE_INGRESS_SECRET`
- `AX_PC_PULL_SECRET`

Do not place secret values in Git, GitHub issues, workflow YAML, logs, or chat.

Use `AX_CONTROL_HUB/AX_SECRET_PROVISION.ps1` or the documented Wrangler commands in `AX_CONTROL_HUB/AX_SECRET_PROVISIONING_RUNBOOK.md`.

## Automated acceptance

After provisioning, dispatch or trigger `.github/workflows/ax-control-runtime-acceptance.yml`.

The workflow verifies:

1. Cloudflare secret presence and minimum length.
2. Deployed Worker health gate.
3. Real `POST /mobile/input` acceptance.
4. Real PC `POST /pc/pull` authentication on the self-hosted Windows/X64 runner.

The production acceptance gate must not be marked PASS from configuration alone; the workflow run must provide fresh evidence.
