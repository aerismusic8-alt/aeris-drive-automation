# PC1: publish the AX Arena place through the Roblox Open Cloud API
#
# This is the path that does not need Roblox Studio. Open Cloud accepts an
# .rbxlx over HTTPS and publishes it as a new place version.
#
# Requires, once, on PC1 or as a GitHub secret:
#   ROBLOX_API_KEY  - an Open Cloud key with universe-places:write
# and roblox-garden/publish-config.json filled in with universeId and placeId.
#
# Without the key this script reports BLOCKED and exits 0, so the workflow
# stays green while the credential is still missing. It never fakes a publish.

param(
  [ValidateSet('Saved', 'Published')]
  [string]$VersionType = ''
)

$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "EXPECTED_PC1:$env:COMPUTERNAME" }

$evidenceDir = 'C:\AX-Runtime\evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$evidencePath = Join-Path $evidenceDir 'pc1-roblox-publish.json'

function Write-Evidence($obj) {
  Set-Content -LiteralPath $evidencePath -Value ($obj | ConvertTo-Json -Depth 6) -Encoding UTF8
}

$placeFile = 'C:\AX-Build\AXGarden.rbxlx'
$configFile = 'C:\AX-Build\repo\roblox-garden\publish-config.json'

# --- Preconditions --------------------------------------------------------
if (!(Test-Path $placeFile)) { throw "PLACE_MISSING:$placeFile (run the build workflow first)" }
if (!(Test-Path $configFile)) { throw "PUBLISH_CONFIG_MISSING:$configFile" }

$config = Get-Content $configFile -Raw | ConvertFrom-Json
$universeId = $config.universeId
$placeId = $config.placeId

# Workflow inputs win over the file. The user drives this from a phone, where
# editing a file in the repo is awkward; typing two numbers into the run form
# is not.
if ($env:UNIVERSE_ID) { $universeId = $env:UNIVERSE_ID }
if ($env:PLACE_ID) { $placeId = $env:PLACE_ID }

$versionType = if ($VersionType) { $VersionType } elseif ($config.versionType) { $config.versionType } else { 'Saved' }

Write-Host "UNIVERSE_ID=$universeId"
Write-Host "PLACE_ID=$placeId"
Write-Host "VERSION_TYPE=$versionType"

$missing = @()
if (!$universeId) { $missing += 'universeId' }
if (!$placeId) { $missing += 'placeId' }
if (!$env:ROBLOX_API_KEY) { $missing += 'ROBLOX_API_KEY' }

if ($missing.Count -gt 0) {
  Write-Host "PUBLISH=BLOCKED"
  Write-Host "MISSING=$($missing -join ',')"
  Write-Evidence ([ordered]@{
    schemaVersion = 1
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    hostname      = $env:COMPUTERNAME
    status        = 'BLOCKED'
    missing       = $missing
    placeFile     = $placeFile
    guidance      = 'Create the experience on create.roblox.com, then run this workflow again with universeId and placeId filled in, and store an Open Cloud key with universe-places:write as ROBLOX_API_KEY.'
  })
  Write-Host "PUBLISH_EVIDENCE=$evidencePath"
  exit 0
}

# --- Publish --------------------------------------------------------------
$uri = "https://apis.roblox.com/universes/v1/$universeId/places/$placeId/versions?versionType=$versionType"
Write-Host "PUBLISH_URL=$uri"

$bytes = [System.IO.File]::ReadAllBytes($placeFile)
Write-Host "UPLOAD_BYTES=$($bytes.Length)"

$headers = @{ 'x-api-key' = $env:ROBLOX_API_KEY }
$response = $null
$statusCode = $null
$errorText = $null

try {
  $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
    -ContentType 'application/xml' -Body $bytes -TimeoutSec 300
  $statusCode = 200
} catch {
  $errorText = $_.Exception.Message
  if ($_.Exception.Response) {
    $statusCode = [int]$_.Exception.Response.StatusCode
    try {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $errorText = $reader.ReadToEnd()
    } catch { }
  }
}

Write-Host "HTTP_STATUS=$statusCode"

if ($statusCode -ne 200) {
  # Never report success without a version number from Roblox.
  Write-Host "PUBLISH=FAILED"
  Write-Host "ERROR=$errorText"
  Write-Evidence ([ordered]@{
    schemaVersion = 1
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    hostname      = $env:COMPUTERNAME
    status        = 'FAILED'
    httpStatus    = $statusCode
    error         = $errorText
    universeId    = $universeId
    placeId       = $placeId
  })
  Write-Host "PUBLISH_EVIDENCE=$evidencePath"
  throw "PUBLISH_FAILED:$statusCode"
}

$versionNumber = $response.versionNumber
if (!$versionNumber) {
  Write-Host "PUBLISH=FAILED"
  Write-Host "ERROR=no versionNumber in response"
  Write-Evidence ([ordered]@{
    schemaVersion = 1
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    hostname      = $env:COMPUTERNAME
    status        = 'FAILED'
    reason        = 'Roblox returned no versionNumber'
    response      = $response
  })
  throw "PUBLISH_NO_VERSION"
}

Write-Host "PUBLISHED_VERSION=$versionNumber"
Write-Host "PUBLISH=COMPLETE"

Write-Evidence ([ordered]@{
  schemaVersion = 1
  capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
  hostname      = $env:COMPUTERNAME
  status        = 'PUBLISHED'
  versionNumber = $versionNumber
  universeId    = $universeId
  placeId       = $placeId
  versionType   = $versionType
  uploadBytes   = $bytes.Length
  placeFile     = $placeFile
})
Write-Host "PUBLISH_EVIDENCE=$evidencePath"
