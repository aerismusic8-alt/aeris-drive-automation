param(
  [string]$StatePath = "$PSScriptRoot\AX_RUNTIME_STATE.json",
  [int]$MaxRetries = 2
)

$ErrorActionPreference = 'Stop'

function Read-State {
  if (-not (Test-Path $StatePath)) {
    return [pscustomobject]@{
      state = 'IDLE'
      retryCount = 0
      lastError = $null
      lastAction = $null
      updatedAt = $null
    }
  }
  return Get-Content -Raw -Path $StatePath | ConvertFrom-Json
}

function Write-State($state) {
  $state.updatedAt = (Get-Date).ToString('o')
  $state | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8
}

$state = Read-State

switch ($state.state) {
  'FAILED' {
    if ([int]$state.retryCount -lt $MaxRetries) {
      $state.retryCount = [int]$state.retryCount + 1
      $state.state = 'RETRYING'
      Write-State $state
      Write-Host "AX_RECOVERY=RETRY retry=$($state.retryCount)/$MaxRetries"
      exit 0
    }

    $state.state = 'BLOCKED'
    Write-State $state
    Write-Host 'AX_RECOVERY=FALLBACK_BLOCKED'
    exit 0
  }
  'RETRYING' {
    $state.state = 'READY'
    Write-State $state
    Write-Host 'AX_RECOVERY=READY_AFTER_RETRY'
    exit 0
  }
  'BLOCKED' {
    Write-Host 'AX_RECOVERY=WAITING_BLOCKED'
    exit 0
  }
  default {
    Write-Host "AX_RECOVERY=HEALTHY state=$($state.state)"
    exit 0
  }
}
