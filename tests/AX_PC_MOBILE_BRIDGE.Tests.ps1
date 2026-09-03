$ErrorActionPreference = 'Stop'

$script = Get-Content (Join-Path $PSScriptRoot '..\AX_CONTROL_HUB\AX_PC_MOBILE_BRIDGE.ps1') -Raw

foreach ($required in @(
    '/pc/pull',
    '/gateway/input',
    '/pc/ack',
    'AX_PC_PULL_SECRET',
    'AX_CONTROL_HUB_USERNAME',
    'AX_CONTROL_HUB_PASSWORD',
    '127.0.0.1:8787',
    'BRIDGE_ACCEPTED',
    'request_id',
    'task_id'
)) {
    if ($script -notmatch [regex]::Escape($required)) {
        throw "BRIDGE_CONTRACT_MISSING:$required"
    }
}

if ($script -match 'AX_MOBILE_INGRESS_SECRET') {
    throw 'BRIDGE_MUST_NOT_HOLD_MOBILE_INGRESS_SECRET'
}

Write-Host 'AX PC/MOBILE bridge contract: PASS'
