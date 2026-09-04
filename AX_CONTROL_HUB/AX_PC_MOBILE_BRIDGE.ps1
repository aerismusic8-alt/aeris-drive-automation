$ErrorActionPreference = 'Stop'

$remoteBase = $env:AX_CONTROL_RUNTIME_URL
if ([string]::IsNullOrWhiteSpace($remoteBase)) { $remoteBase = 'https://ax-control-runtime.aerismusic8.workers.dev' }
$localBase = $env:AX_CONTROL_HUB_URL
if ([string]::IsNullOrWhiteSpace($localBase)) { $localBase = 'http://127.0.0.1:8787' }

if ([string]::IsNullOrWhiteSpace($env:AX_PC_PULL_SECRET)) { throw 'AX_PC_PULL_SECRET_NOT_CONFIGURED' }
if ([string]::IsNullOrWhiteSpace($env:AX_CONTROL_HUB_USERNAME)) { throw 'AX_CONTROL_HUB_USERNAME_NOT_CONFIGURED' }
if ($null -eq $env:AX_CONTROL_HUB_PASSWORD) { throw 'AX_CONTROL_HUB_PASSWORD_NOT_CONFIGURED' }

function Invoke-Json($uri, $method, $headers, $body) {
    if ($null -eq $body) {
        return Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -TimeoutSec 30
    }
    return Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 12) -TimeoutSec 30
}

Write-Host "AX PC/MOBILE bridge starting. Remote=$remoteBase Local=$localBase"

$login = Invoke-Json "$localBase/auth/login" 'POST' @{} @{ username = $env:AX_CONTROL_HUB_USERNAME; password = $env:AX_CONTROL_HUB_PASSWORD }
if (-not $login.authenticated -or [string]::IsNullOrWhiteSpace($login.token)) { throw 'LOCAL_CONTROL_HUB_LOGIN_FAILED' }
$localAuth = @{ Authorization = "Bearer $($login.token)" }
$remoteAuth = @{ Authorization = "Bearer $($env:AX_PC_PULL_SECRET)" }

while ($true) {
    try {
        $pulled = Invoke-Json "$remoteBase/pc/pull" 'POST' $remoteAuth $null
        if ($null -eq $pulled.item) {
            Start-Sleep -Seconds 3
            continue
        }

        $item = $pulled.item
        $sourceChannel = if ([string]::IsNullOrWhiteSpace([string]$item.source_channel)) { 'MOBILE' } else { [string]$item.source_channel }
        $gatewayPayload = @{
            request_id = $item.request_id
            task_id = $item.task_id
            idempotency_key = "AX-EXT-$($item.request_id)"
            source_channel = $sourceChannel
            content_type = $item.content_type
            content = $item.content
            attachments = $item.attachments
        }

        $accepted = Invoke-Json "$localBase/gateway/input" 'POST' $localAuth $gatewayPayload
        if ([string]$accepted.request_id -ne [string]$item.request_id) {
            throw "LOCAL_REQUEST_ID_MISMATCH:$($item.request_id)"
        }

        $resultPayload = @{
            request_id = $item.request_id
            task_id = $item.task_id
            result = $accepted
        }
        $stored = Invoke-Json "$remoteBase/pc/result" 'POST' $remoteAuth $resultPayload
        if (-not $stored.ok) { throw "REMOTE_RESULT_STORE_FAILED:$($item.request_id)" }

        $ack = Invoke-Json "$remoteBase/pc/ack" 'POST' $remoteAuth @{ request_id = $item.request_id }
        if (-not $ack.ok) { throw "REMOTE_ACK_FAILED:$($item.request_id)" }

        Write-Host "BRIDGE_ACCEPTED request_id=$($item.request_id) task_id=$($item.task_id) source_channel=$sourceChannel result_returned=true"
    }
    catch {
        Write-Warning "AX PC/MOBILE bridge cycle failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 5
    }
}
