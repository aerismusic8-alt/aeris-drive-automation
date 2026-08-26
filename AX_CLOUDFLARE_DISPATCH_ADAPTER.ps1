param(
  [Parameter(Mandatory=$true)][string]$TaskId,
  [Parameter(Mandatory=$true)][string]$Domain,
  [Parameter(Mandatory=$true)][int]$Priority,
  [Parameter(Mandatory=$true)][string]$Action,
  [string]$RuntimeUrl = $env:AX_CLOUDFLARE_RUNTIME_URL,
  [string]$Repository = $env:GITHUB_REPOSITORY,
  [string]$GitHubToken = $env:GITHUB_TOKEN
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RuntimeUrl)) { throw 'AX_CLOUDFLARE_RUNTIME_URL_REQUIRED' }
if ([string]::IsNullOrWhiteSpace($GitHubToken)) { throw 'GITHUB_TOKEN_REQUIRED' }
if ([string]::IsNullOrWhiteSpace($Repository)) { throw 'GITHUB_REPOSITORY_REQUIRED' }

& powershell.exe -ExecutionPolicy Bypass -File "$PSScriptRoot\AX_RESOURCE_GOVERNOR.ps1" -EstimatedWorkerRequests 1 -EstimatedQueueOperations 3 -EstimatedWorkflowSteps 0
if ($LASTEXITCODE -ne 0) { throw "AX_RESOURCE_GOVERNOR_BLOCKED:$LASTEXITCODE" }

$event = @{
  id = [guid]::NewGuid().ToString()
  taskId = $TaskId
  domain = $Domain
  priority = $Priority
  action = $Action
  createdAt = (Get-Date).ToUniversalTime().ToString('o')
  source = 'AX_EXECUTIVE_LOOP'
} | ConvertTo-Json -Compress

$headers = @{
  Authorization = "Bearer $GitHubToken"
  'X-AERIS-REPOSITORY' = $Repository
  Accept = 'application/json'
  'Content-Type' = 'application/json'
}

$response = Invoke-RestMethod -Uri "$RuntimeUrl/enqueue" -Method Post -Headers $headers -Body $event
if ($response.accepted -ne $true -or $response.queued -ne $true) { throw 'AX_CLOUDFLARE_QUEUE_REJECTED' }
Write-Host "AX_CLOUDFLARE_DISPATCH=ACCEPTED eventId=$($response.eventId)"
