$ErrorActionPreference = 'Stop'
$gatewayPath = Join-Path $PSScriptRoot '..\AX_PC_DISPATCH_GATEWAY.ps1'
if (-not (Test-Path $gatewayPath)) { throw 'RED: AX_PC_DISPATCH_GATEWAY.ps1 is missing' }

. $gatewayPath

$event = New-AxPcDispatchEvent -TaskId 'TEST-PC2-001' -Command 'health' -Arguments @{} -NodeId 'PC2-CODING-EXECUTOR'
if ([string]::IsNullOrWhiteSpace($event.requestId)) { throw 'requestId missing' }
if ($event.taskId -ne 'TEST-PC2-001') { throw 'taskId mismatch' }
if ($event.nodeId -ne 'PC2-CODING-EXECUTOR') { throw 'nodeId mismatch' }
if ($event.command -ne 'health') { throw 'command mismatch' }

$allowed = Test-AxPcDispatchCompletion -Lifecycle @('QUEUED','PULLED','EXECUTED','RESULT_RECEIVED','ACK_RECEIVED')
if ($allowed) { throw 'RED: unverified lifecycle must not be accepted as complete' }

$verified = Test-AxPcDispatchCompletion -Lifecycle @('QUEUED','PULLED','EXECUTED','RESULT_RECEIVED','ACK_RECEIVED','VERIFIED')
if (-not $verified) { throw 'verified lifecycle must be accepted' }

Write-Output 'PASS: AX PC Dispatch Gateway contract'
