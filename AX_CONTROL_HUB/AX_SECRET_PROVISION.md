# AX Secret Provisioning — Operator Gate

This file exists because the runtime is fail-closed until the two Worker secrets are configured.

Required one-time operator action on the target Cloudflare account:

```powershell
Set-Location <repo-root>
.\AX_CONTROL_HUB\AX_SECRET_PROVISION.ps1
```

The script prompts for both secrets and sends them to Cloudflare using Wrangler. Secret values are not stored in Git, printed by the script, or returned by the health check.

Acceptance gate after provisioning:

- `status=ONLINE`
- `mode=FREE_ONLY`
- `liveFinancialExecution=false`
- `mobileIngressAuthConfigured=true`
- `pcPullAuthConfigured=true`
- `gatewayInbox=AX_GATEWAY_INBOX`

Do not copy secrets into chat, issues, commits, workflow YAML, or documentation.
