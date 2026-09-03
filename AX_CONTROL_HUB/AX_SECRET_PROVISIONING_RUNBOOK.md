# AX Secret Provisioning Runbook

Required one-time operator action on the target Cloudflare account:

```powershell
Set-Location <repo-root>
npx wrangler@latest secret put AX_MOBILE_INGRESS_SECRET --name ax-control-runtime
npx wrangler@latest secret put AX_PC_PULL_SECRET --name ax-control-runtime
```

Use unique high-entropy values of at least 32 characters. Never paste secret values into Git, chat, issues, workflow YAML, logs, or documentation.

Verify only the boolean health state:

```powershell
Invoke-RestMethod https://ax-control-runtime.aerismusic8.workers.dev/health | Select-Object status,mode,liveFinancialExecution,mobileIngressAuthConfigured,pcPullAuthConfigured,gatewayInbox
```

Required:
- status = ONLINE
- mode = FREE_ONLY
- liveFinancialExecution = False
- mobileIngressAuthConfigured = True
- pcPullAuthConfigured = True
- gatewayInbox = AX_GATEWAY_INBOX
