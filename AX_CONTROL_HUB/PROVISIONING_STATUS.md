# AX Provisioning Status

Current known state: Cloudflare Worker deployment is active, but Mobile and PC bearer authentication remain unconfigured until the two Worker secrets are provisioned.

This is intentionally fail-closed. Do not mark the production acceptance gate as passed until `/health` reports both `mobileIngressAuthConfigured=true` and `pcPullAuthConfigured=true`.

Provisioning instructions are in `AX_CONTROL_HUB/AX_SECRET_PROVISIONING_RUNBOOK.md`.
