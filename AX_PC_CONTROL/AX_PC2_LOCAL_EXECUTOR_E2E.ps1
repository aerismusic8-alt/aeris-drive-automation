param(
    [string]$JobId = "AX-PC2-E2E-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))"
)

$ErrorActionPreference = 'Stop'
$expected = 'DESKTOP-M9M4818'
if ($env:COMPUTERNAME -ne $expected) { throw "PC2_EXECUTOR_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$runtimeRoot = 'C:\AX-Runtime'
$statePath = Join-Path $runtimeRoot 'AX-PC2-Worker-State.json'
$proofDir = Join-Path $runtimeRoot 'proof'
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
New-Item -ItemType Directory -Path $proofDir -Force | Out-Null

$started = [DateTime]::UtcNow
$state = [ordered]@{
    protocol = 'AX PC2 LOCAL EXECUTOR v1'
    nodeId = 'PC2'
    status = 'RUNNING'
    currentJobId = $JobId
    currentAttempt = 1
    currentPayload = @{ command = 'NODE_E2E_TEST'; source = 'github-actions' }
    liveFinancialExecution = $false
    updatedAt = $started.ToString('o')
}
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $statePath -Encoding UTF8

# Real local execution proof: create a tangible MP4 on PC2.
$toolRoot = Join-Path $runtimeRoot 'tools\ffmpeg'
$ffmpeg = Join-Path $toolRoot 'ffmpeg.exe'
if (-not (Test-Path $ffmpeg)) {
    New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
    $zip = Join-Path $runtimeRoot 'ffmpeg-essentials.zip'
    $url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    $extract = Join-Path $toolRoot 'extract'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $extract -Force
    $found = Get-ChildItem $extract -Filter 'ffmpeg.exe' -Recurse -File | Select-Object -First 1
    if (-not $found) { throw 'FFMPEG_DOWNLOAD_NO_BINARY' }
    Copy-Item $found.FullName $ffmpeg -Force
    Remove-Item $extract -Recurse -Force
    Remove-Item $zip -Force
}
if (-not (Test-Path $ffmpeg)) { throw 'FFMPEG_NOT_FOUND_ON_PC2' }
$mediaDir = Join-Path $runtimeRoot 'media'
New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null
$mediaPath = Join-Path $mediaDir "$JobId.mp4"
& $ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=720x1280:rate=30" -t 3 -pix_fmt yuv420p $mediaPath
if ($LASTEXITCODE -ne 0) { throw "FFMPEG_EXIT:$LASTEXITCODE" }
if (-not (Test-Path $mediaPath)) { throw 'MEDIA_OUTPUT_MISSING' }
$mediaInfo = Get-Item $mediaPath
if ($mediaInfo.Length -le 10000) { throw 'MEDIA_OUTPUT_TOO_SMALL' }

# Safe local execution proof. No external control API, Apps Script, or secret is used.
$proof = [ordered]@{
    protocol = 'AX PC2 LOCAL EXECUTOR v1'
    jobId = $JobId
    nodeId = 'PC2'
    command = 'NODE_E2E_TEST'
    executed = $true
    verified = $true
    liveFinancialExecution = $false
    startedAt = $started.ToString('o')
    completedAt = [DateTime]::UtcNow.ToString('o')
    executionHost = $env:COMPUTERNAME
}
$proofPath = Join-Path $proofDir "$JobId.json"
$proof | ConvertTo-Json -Depth 20 | Set-Content -Path $proofPath -Encoding UTF8

$state.status = 'COMPLETED'
$state.currentPayload = $proof
$state.updatedAt = [DateTime]::UtcNow.ToString('o')
$state | ConvertTo-Json -Depth 20 | Set-Content -Path $statePath -Encoding UTF8

Write-Host "PC2_LOCAL_EXECUTOR_JOB=$JobId"
Write-Host 'PC2_LOCAL_EXECUTOR=VERIFIED'
Write-Host 'PC2_WORKER_E2E=VERIFIED'
Write-Host 'STATE=COMPLETED'
Write-Host "PROOF=$proofPath"
