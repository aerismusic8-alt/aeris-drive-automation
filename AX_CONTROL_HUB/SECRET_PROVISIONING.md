# AX Secret Provisioning

The AX Cloudflare Control Runtime requires two Worker secrets:

- `AX_MOBILE_INGRESS_SECRET`
- `AX_PC_PULL_SECRET`

## Security rule

Never commit secret values to the repository, workflow files, logs, issues, or chat.

## Provision

Run the following with Wrangler while authenticated to the target Cloudflare account:

```bash
npx wrangler secret put AX_MOBILE_INGRESS_SECRET --name ax-control-runtime
npx wrangler secret put AX_PC_PULL_SECRET --name ax-control-runtime
```

Each value must be a unique high-entropy bearer secret of at least 32 characters.

After provisioning, verify only the boolean health fields:

```bash
curl -fsS https://ax-control-runtime.aerismusic8.workers.dev/health
```

Required values:

```text
status=ONLINE
mode=FREE_ONLY
liveFinancialExecution=false
mobileIngressAuthConfigured=true
pcPullAuthConfigured=true
gatewayInbox=AX_GATEWAY_INBOX
```

The secret values themselves must never be displayed or recorded in repository files.
