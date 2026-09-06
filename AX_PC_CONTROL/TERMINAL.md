# AX Remote Terminal

## Request format

Send a `command` content type through the existing AX Control Runtime. The content is JSON:

```json
{
  "operation": "terminal-powershell",
  "args": {
    "command": "Get-Service | Select-Object -First 10 Name,Status"
  }
}
```

The node must be online and authenticated with `AX_PC_PULL_SECRET`.

## Administrative examples

Runner status:

```json
{"operation":"runner-status","args":{}}
```

Restart the GitHub Actions runner:

```json
{"operation":"runner-restart","args":{}}
```

Check a Windows service:

```json
{"operation":"service-status","args":{"name":"AX-PC-NODE-PC1"}}
```

## Bootstrap

Run `INSTALL_AX_PC_NODE.ps1` from an elevated PowerShell session on each target machine. The installer creates the node directory, stores the transport secret as a machine environment variable, installs the node as an automatic Windows service, and starts it.

Do not commit `AX_PC_NODE_CONFIG.json` or transport secrets to Git.

## Operational gate

Installing the code in GitHub is not proof of remote control. Completion requires evidence from the real PC:

1. node service running;
2. `/pc/pull` authenticated;
3. `health` command executed;
4. result returned and ACKed;
5. administrative terminal command executed;
6. GitHub Actions runner status observed;
7. `workflow_dispatch` job picked up by PC1 or PC2;
8. downstream execution verified.
