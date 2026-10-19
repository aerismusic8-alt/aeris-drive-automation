# PC1: install Rojo and build the AX Arena place file
#
# Rojo turns this repo into a Roblox place without needing Roblox Studio.
# The output is AXArena.rbxlx, which a human opens once in Studio to publish.
#
# Writes to C:\AX-Build\ and reports JSON evidence.

$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "EXPECTED_PC1:$env:COMPUTERNAME" }

$buildRoot = 'C:\AX-Build'
$rojoDir   = Join-Path $buildRoot 'tools\rojo'
$repoDir   = Join-Path $buildRoot 'repo'
$evidenceDir = 'C:\AX-Runtime\evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null

$ROJO_VERSION = '7.7.1'
$ROJO_URL = "https://github.com/rojo-rbx/rojo/releases/download/v$ROJO_VERSION/rojo-$ROJO_VERSION-windows-x86_64.zip"

Write-Host "BUILD_ROOT=$buildRoot"

# --- 1. Install Rojo if missing -------------------------------------------
$rojoExe = Join-Path $rojoDir 'rojo.exe'
if (!(Test-Path $rojoExe)) {
  Write-Host "ROJO_INSTALL=starting"
  New-Item -ItemType Directory -Path $rojoDir -Force | Out-Null
  $zip = Join-Path $env:TEMP "rojo-$ROJO_VERSION.zip"
  Invoke-WebRequest -Uri $ROJO_URL -OutFile $zip -UseBasicParsing
  Expand-Archive -Path $zip -DestinationPath $rojoDir -Force
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  if (!(Test-Path $rojoExe)) { throw "ROJO_EXE_MISSING_AFTER_EXTRACT:$rojoExe" }
  Write-Host "ROJO_INSTALL=done"
} else {
  Write-Host "ROJO_INSTALL=already-present"
}

$rojoVersion = (& $rojoExe --version 2>&1 | Out-String).Trim()
Write-Host "ROJO_VERSION=$rojoVersion"

# --- 2. Get the repo ------------------------------------------------------
$REPO_URL = 'https://github.com/aerismusic8-alt/aeris-drive-automation.git'
$BRANCH = 'ax-arena-roblox-game'

if (Test-Path (Join-Path $repoDir '.git')) {
  Write-Host "REPO=syncing"
  & git -C $repoDir fetch --depth 1 origin $BRANCH
  & git -C $repoDir checkout -f FETCH_HEAD
  & git -C $repoDir clean -fdx
} else {
  Write-Host "REPO=cloning"
  New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
  & git clone --depth 1 --branch $BRANCH $REPO_URL $repoDir
}
if ($LASTEXITCODE -ne 0) { throw "GIT_FAILED:$LASTEXITCODE" }

$robloxDir = Join-Path $repoDir 'roblox'
if (!(Test-Path (Join-Path $robloxDir 'default.project.json'))) {
  throw "PROJECT_FILE_MISSING"
}
Write-Host "REPO_READY=$robloxDir"

# --- 3. Build the place ---------------------------------------------------
$outFile = Join-Path $buildRoot 'AXArena.rbxlx'
Push-Location $robloxDir
try {
  & $rojoExe build default.project.json --output $outFile
  if ($LASTEXITCODE -ne 0) { throw "ROJO_BUILD_EXIT:$LASTEXITCODE" }
} finally {
  Pop-Location
}

if (!(Test-Path $outFile)) { throw "BUILD_OUTPUT_MISSING:$outFile" }
$outSize = (Get-Item $outFile).Length
Write-Host "BUILD_OUTPUT=$outFile"
Write-Host "BUILD_SIZE_BYTES=$outSize"

# --- 4. Sanity check the place actually contains our scripts -------------
# Rojo stores Luau source in <string name="Source">, not ProtectedString.
# Checking for a script's *name* alone is not enough: an empty script still
# has a name. So we count real source blocks and look for markers that only
# appear in our code.
$xml = Get-Content $outFile -Raw

$sourceBlocks = ([regex]::Matches($xml, '<string\s+name="Source">')).Count
Write-Host "SOURCE_BLOCKS=$sourceBlocks"
if ($sourceBlocks -lt 20) { throw "SOURCE_BLOCKS_TOO_FEW:$sourceBlocks (expected >=20)" }

# Markers prove the *code* made it in, not just the instance names.
$markers = [ordered]@{
  config        = 'BaseXp'
  leveling      = 'xpFromKill'
  pets          = 'rarity'
  rebirth       = 'MaxRebirths'
  zones         = 'coinMultiplier'
  monetization  = 'ProcessReceipt'
  saveSchema    = 'SchemaVersion'
  serverLoop    = 'Heartbeat'
  clientIntent  = 'InvokeServer'
  rateLimiter   = 'RateLimiter'
  world         = 'buildWorld'
  fields        = 'spawnPoint'
  travel        = 'TravelZone'
  boss          = 'bossInfo'
  hud           = 'AXArenaHUD'
  travelPanel   = 'TravelPanel'
  dailyRewards  = 'canClaim'
  codes         = 'hasRedeemed'
  farm          = 'plantedCount'
  axe           = 'swingDamage'
}
$checks = [ordered]@{ sourceBlocks = $sourceBlocks }
foreach ($k in $markers.Keys) {
  $found = $xml.Contains($markers[$k])
  $checks[$k] = $found
  Write-Host ("CHECK_{0}={1}" -f $k.ToUpper(), $found)
}
if ($checks.Values -contains $false) {
  $bad = @($checks.Keys | Where-Object { $checks[$_] -eq $false })
  throw "PLACE_CONTENT_INCOMPLETE:$($bad -join ',')"
}

# Every script instance must carry a non-empty source block.
$scriptTags = ([regex]::Matches($xml, 'class="(ModuleScript|Script|LocalScript)"')).Count
Write-Host "SCRIPT_INSTANCES=$scriptTags"
if ($sourceBlocks -lt $scriptTags) {
  throw "EMPTY_SCRIPT_PRESENT:instances=$scriptTags sources=$sourceBlocks"
}

$result = [ordered]@{
  schemaVersion = 1
  capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
  hostname      = $env:COMPUTERNAME
  rojo          = [ordered]@{ version = $rojoVersion; path = $rojoExe }
  repo          = [ordered]@{ path = $repoDir; branch = $BRANCH }
  build         = [ordered]@{ output = $outFile; sizeBytes = $outSize }
  contentChecks = $checks
  status        = 'BUILT'
}

$out = Join-Path $evidenceDir 'pc1-roblox-build.json'
Set-Content -LiteralPath $out -Value ($result | ConvertTo-Json -Depth 6) -Encoding UTF8
Write-Host "BUILD_EVIDENCE=$out"
Write-Host "BUILD=COMPLETE"
