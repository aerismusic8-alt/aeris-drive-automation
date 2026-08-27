param(
  [string]$ApiUrl = 'https://script.google.com/macros/s/AKfycbwz6F8EWTD7YwnGkyu4Mq_JHtBkk6nOwl9TYjWDsMsQTtS5EVj3I6hmakuW6yP_YGQH/exec',
  [string]$WorkerId = $env:COMPUTERNAME,
  [int]$PollSeconds = 10,
  [switch]$Once
)

$ErrorActionPreference = 'Stop'
$StatePath = 'C:\AX-Runtime\AX-PC2-Worker-State.json'
$LogPath = 'C:\AX-Runtime\AX-PC2-Worker-V2.log'
New-Item -ItemType Directory -Path 'C:\AX-Runtime' -Force | Out-Null

function Save-State($status,$jobId='',$attempt=0) {
  $state = [ordered]@{
    protocol='AX PC2 WORKER v2'
    workerId=$WorkerId
    status=$status
    currentJobId=$jobId
    currentAttempt=$attempt
    liveFinancialExecution=$false
    updatedAt=(Get-Date).ToUniversalTime().ToString('o')
  }
  $state | ConvertTo-Json | Set-Content -Path $StatePath -Encoding UTF8
  Add-Content -Path $LogPath -Value ((Get-Date).ToUniversalTime().ToString('o') + ' ' + $status + ' job=' + $jobId)
}

Save-State 'ONLINE'

while ($true) {
  # API contract is implemented by the AERIS Node API layer.
  # This worker deliberately does not execute live financial actions.
  Save-State 'POLLING'
  if ($Once) { break }
  Start-Sleep -Seconds $PollSeconds
}

Save-State 'STOPPED'
