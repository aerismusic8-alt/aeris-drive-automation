param(
    [Parameter(Mandatory=$true)][ValidateSet('technical','independent-review','recovery','architecture')][string]$Specialty,
    [Parameter(Mandatory=$true)][string]$Prompt,
    [Parameter(Mandatory=$true)][string]$TargetFile
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$registryPath = Join-Path $PSScriptRoot 'AX_AI_EXECUTOR_ESCALATION_REGISTRY.json'
if (-not (Test-Path $registryPath)) { throw 'CANONICAL_AI_REGISTRY_MISSING' }
$registry = Get-Content -Raw $registryPath | ConvertFrom-Json
if ($registry.canonical -ne $true) { throw 'CANONICAL_AI_REGISTRY_INVALID' }

$candidates = @($registry.routingRules.$Specialty)
if (-not $candidates) { throw "NO_SPECIALIST_ROUTE:$Specialty" }

foreach ($id in $candidates) {
    $specialist = @($registry.specialists | Where-Object { $_.id -eq $id -and $_.enabled -eq $true }) | Select-Object -First 1
    if (-not $specialist) { continue }
    Write-Host "SPECIALIST_CANDIDATE=$($specialist.id)"
    Write-Host "SPECIALIST_PROVIDER=$($specialist.provider)"
    Write-Host "SPECIALIST_TRANSPORT=$($specialist.transport)"
    Write-Host "SPECIALIST_LIVE_VERIFIED=$($specialist.liveVerified)"

    if (-not $specialist.liveVerified) {
        Write-Host "SPECIALIST_ROUTE_BLOCKED_UNVERIFIED=$($specialist.id)"
        continue
    }

    switch ($specialist.id) {
        'AI-01-OPENAI' {
            gh workflow run ax-openai-live-code-stream.yml --ref main -f prompt=$Prompt -f file=$TargetFile
            if ($LASTEXITCODE -ne 0) { throw 'OPENAI_SPECIALIST_DISPATCH_FAILED' }
        }
        'AI-02-GEMINI-API' {
            gh workflow run ax-gemini-api-worker.yml --ref main -f prompt=$Prompt -f file=$TargetFile
            if ($LASTEXITCODE -ne 0) { throw 'GEMINI_API_SPECIALIST_DISPATCH_FAILED' }
        }
        'AI-03-GEMINI-CLOUDFLARE' {
            throw 'GEMINI_CLOUDFLARE_SPECIALIST_REQUIRES_WORKFLOW_INPUT_ADAPTER'
        }
        'AI-04-GEMINI-LIVE-CODE-STREAM' {
            gh workflow run ax-gemini-live-code-stream.yml --ref main -f prompt=$Prompt -f file=$TargetFile
            if ($LASTEXITCODE -ne 0) { throw 'GEMINI_LIVE_SPECIALIST_DISPATCH_FAILED' }
        }
    }
    Write-Host "ESCALATION_DISPATCHED=$($specialist.id)"
    exit 0
}

throw "NO_VERIFIED_SPECIALIST_AVAILABLE:$Specialty"
