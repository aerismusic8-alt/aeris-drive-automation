# PC1: list the places of a universe through the Open Cloud API.
#
# The dashboard hides the place id behind a click; the API returns it. This
# opens no window and takes seconds, so it is safe to run on PC1.
#
# Needs repo secret ROBLOX_API_KEY with universe-places read scope.
# Writes C:\AX-Runtime\evidence\pc1-roblox-list-places.json

$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "EXPECTED_PC1:$env:COMPUTERNAME" }

$universeId = $env:UNIVERSE_ID
if (!$universeId) { throw "UNIVERSE_ID_MISSING" }
if (!$env:ROBLOX_API_KEY) { throw "ROBLOX_API_KEY_MISSING" }

$evidenceDir = 'C:\AX-Runtime\evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$evidencePath = Join-Path $evidenceDir 'pc1-roblox-list-places.json'

$uri = "https://apis.roblox.com/cloud/v2/universes/$universeId/places?maxPageSize=50"
Write-Host "LIST_URL=$uri"

$statusCode = $null
$body = $null
try {
  $body = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ 'x-api-key' = $env:ROBLOX_API_KEY } -TimeoutSec 60
  $statusCode = 200
} catch {
  if ($_.Exception.Response) {
    $statusCode = [int]$_.Exception.Response.StatusCode
    try {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $body = $reader.ReadToEnd()
    } catch { $body = $_.Exception.Message }
  } else {
    $body = $_.Exception.Message
  }
}

Write-Host "HTTP_STATUS=$statusCode"
$raw = ($body | ConvertTo-Json -Depth 8 -Compress)

$places = @()
if ($statusCode -eq 200) {
  foreach ($p in @($body.places)) {
    # The id also lives at the end of the resource path.
    $id = $p.id
    if (!$id -and $p.path) { $id = ($p.path -split '/')[-1] }
    $places += [ordered]@{ id = "$id"; name = "$($p.displayName)" }
    Write-Host ("PLACE_ID={0} NAME={1}" -f $id, $p.displayName)
  }
  if ($places.Count -eq 0) { Write-Host "PLACE_COUNT=0" }
} else {
  Write-Host "PLACE_LIST=FAILED"
  Write-Host "ERROR=$raw"
}

([ordered]@{
  schemaVersion = 1
  capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
  hostname      = $env:COMPUTERNAME
  universeId    = $universeId
  httpStatus    = $statusCode
  placeCount    = $places.Count
  places        = $places
}) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

Write-Host "PLACES_EVIDENCE=$evidencePath"

if ($statusCode -ne 200) { exit 1 }
