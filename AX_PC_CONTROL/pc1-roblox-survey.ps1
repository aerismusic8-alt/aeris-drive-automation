# PC1 Roblox toolchain survey
#
# Read-only. Reports whether the Roblox publishing toolchain exists on PC1 so
# AX can choose a publish path without guessing. It never reads credentials,
# cookies or tokens; it only tests for presence.
#
# Writes C:\AX-Runtime\evidence\pc1-roblox-survey.json

$ErrorActionPreference = 'Stop'

if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "EXPECTED_PC1:$env:COMPUTERNAME" }

$evidenceDir = 'C:\AX-Runtime\evidence'
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

function Test-PathSafe($p) {
  try { return [bool](Test-Path -LiteralPath $p) } catch { return $false }
}

# --- Roblox Studio ---------------------------------------------------------
$studioRoot = Join-Path $env:LOCALAPPDATA 'Roblox\Versions'
$studioExes = @()
if (Test-PathSafe $studioRoot) {
  $studioExes = @(Get-ChildItem -Path $studioRoot -Recurse -Filter 'RobloxStudioBeta.exe' -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName)
}

$studioVersion = $null
if ($studioExes.Count -gt 0) {
  $studioVersion = (Get-Item -LiteralPath $studioExes[0]).VersionInfo.ProductVersion
}

# --- Roblox Player ---------------------------------------------------------
$playerExes = @()
if (Test-PathSafe $studioRoot) {
  $playerExes = @(Get-ChildItem -Path $studioRoot -Recurse -Filter 'RobloxPlayerBeta.exe' -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty FullName)
}

# --- Roblox Studio presence in registry (install marker only) --------------
$studioRegistry = Test-PathSafe 'HKCU:\Software\Roblox\RobloxStudioBrowser'

# --- Does a signed-in Roblox session exist? (presence only, never contents) -
$localStorage = Join-Path $env:LOCALAPPDATA 'Roblox\LocalStorage'
$hasSessionMarker = Test-PathSafe $localStorage

# --- Roblox Studio plugins / published place cache ------------------------
$studioPlugins = Join-Path $env:LOCALAPPDATA 'Roblox\Plugins'
$hasPlugins = Test-PathSafe $studioPlugins

# --- Rojo (the tool that turns this repo into a .rbxl) --------------------
$rojo = Get-Command rojo -ErrorAction SilentlyContinue
$rojoPath = if ($rojo) { $rojo.Source } else { $null }

# --- Supporting toolchain -------------------------------------------------
$tools = [ordered]@{}
foreach ($name in @('git','node','npm','python','pwsh','powershell')) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  $tools[$name] = if ($cmd) { $cmd.Source } else { $null }
}

$gitVersion = $null
try { $gitVersion = (& git --version 2>$null) } catch { }

# --- Interactive session --------------------------------------------------
$interactiveUser = (Get-CimInstance Win32_ComputerSystem).UserName

# --- Existing AX workspace on this machine --------------------------------
$axRoots = @('C:\AX-Bootstrap', 'C:\AX-Runtime', 'C:\AX', "$env:USERPROFILE\aeris-drive-automation")
$axPresent = @($axRoots | Where-Object { Test-PathSafe $_ })

$result = [ordered]@{
  schemaVersion = 1
  capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
  hostname      = $env:COMPUTERNAME
  interactiveUser = $interactiveUser

  studio = [ordered]@{
    installed     = ($studioExes.Count -gt 0)
    exePaths      = $studioExes
    version       = $studioVersion
    registryMarker = $studioRegistry
    versionsRoot  = $studioRoot
  }

  player = [ordered]@{
    installed = ($playerExes.Count -gt 0)
    exePaths  = $playerExes
  }

  session = [ordered]@{
    localStoragePresent = $hasSessionMarker
    pluginsPresent      = $hasPlugins
  }

  rojo = [ordered]@{
    installed = [bool]$rojoPath
    path      = $rojoPath
  }

  tools = $tools
  gitVersion = $gitVersion
  axRootsPresent = $axPresent
}

$json = $result | ConvertTo-Json -Depth 6
$out = Join-Path $evidenceDir 'pc1-roblox-survey.json'
Set-Content -LiteralPath $out -Value $json -Encoding UTF8

# --- Human-readable summary ----------------------------------------------
Write-Host "SURVEY_FILE=$out"
Write-Host "HOSTNAME=$($result.hostname)"
Write-Host "INTERACTIVE_USER=$interactiveUser"
Write-Host "STUDIO_INSTALLED=$($result.studio.installed)"
Write-Host "STUDIO_VERSION=$studioVersion"
Write-Host "STUDIO_EXE_COUNT=$($studioExes.Count)"
Write-Host "PLAYER_INSTALLED=$($result.player.installed)"
Write-Host "SESSION_MARKER=$hasSessionMarker"
Write-Host "ROJO_INSTALLED=$($result.rojo.installed)"
foreach ($k in $tools.Keys) {
  Write-Host ("TOOL_{0}={1}" -f $k.ToUpper(), $(if ($tools[$k]) { 'PRESENT' } else { 'MISSING' }))
}
Write-Host "AX_ROOTS=$($axPresent -join ',')"
Write-Host "SURVEY=COMPLETE"
