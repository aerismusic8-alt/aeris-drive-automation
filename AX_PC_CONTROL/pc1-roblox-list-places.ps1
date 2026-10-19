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

$headers = @{ 'x-api-key' = $env:ROBLOX_API_KEY }

function Get-Json($uri) {
  try {
    return @{ code = 200; body = (Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec 60) }
  } catch {
    if ($_.Exception.Response) {
      $code = [int]$_.Exception.Response.StatusCode
      $text = $_.Exception.Message
      try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $text = $reader.ReadToEnd()
      } catch { }
      return @{ code = $code; body = $text }
    }
    return @{ code = 0; body = $_.Exception.Message }
  }
}

# The universe resource carries the name and the visibility flag. Visibility is
# read-only over the API, but reading it says whether the game is live yet.
$uniUri = "https://apis.roblox.com/cloud/v2/universes/$universeId"
$uni = Get-Json $uniUri
Write-Host "UNIVERSE_HTTP_STATUS=$($uni.code)"
if ($uni.code -eq 200) {
  Write-Host "UNIVERSE_NAME=$($uni.body.displayName)"
  Write-Host "UNIVERSE_VISIBILITY=$($uni.body.visibility)"
  Write-Host "UNIVERSE_DESCRIPTION=$($uni.body.description)"
} else {
  Write-Host "UNIVERSE_ERROR=$(($uni.body | ConvertTo-Json -Depth 6 -Compress))"
}

$uri = "https://apis.roblox.com/cloud/v2/universes/$universeId/places?maxPageSize=50"
Write-Host "LIST_URL=$uri"

$placesResult = Get-Json $uri
$statusCode = $placesResult.code
$body = $placesResult.body

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
