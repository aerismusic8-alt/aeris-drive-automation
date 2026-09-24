$ErrorActionPreference = 'Stop'
$expected = 'DESKTOP-M9M4818'
if ($env:COMPUTERNAME -ne $expected) { throw "PC2_IDENTITY_MISMATCH:$env:COMPUTERNAME" }

$protectedPatterns = @(
  'brain2','brain-2','brain','control2','control-2','akath','ax-runtime'
)

$targets = Get-Process | Where-Object {
  $_.MainWindowHandle -ne 0 -and
  $_.MainWindowTitle -match '(?i)(Windows Terminal|PowerShell|Command Prompt|cmd.exe)'
}

$closed = @()
$skipped = @()

foreach ($p in $targets) {
  $name = [string]$p.ProcessName
  $title = [string]$p.MainWindowTitle
  $cmd = ''
  try {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction Stop).CommandLine
  } catch {}

  $protected = $false
  foreach ($pat in $protectedPatterns) {
    if ($name -match $pat -or $title -match $pat -or $cmd -match $pat) { $protected = $true; break }
  }

  if ($protected) {
    $skipped += [pscustomobject]@{ pid=$p.Id; process=$name; title=$title; reason='protected-runtime' }
    continue
  }

  try {
    if ($p.CloseMainWindow()) {
      Start-Sleep -Milliseconds 800
      if (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) {
        $closed += [pscustomobject]@{ pid=$p.Id; process=$name; title=$title; result='closed' }
      } else {
        $skipped += [pscustomobject]@{ pid=$p.Id; process=$name; title=$title; reason='did-not-exit-after-close' }
      }
    } else {
      $skipped += [pscustomobject]@{ pid=$p.Id; process=$name; title=$title; reason='close-request-rejected' }
    }
  } catch {
    $skipped += [pscustomobject]@{ pid=$p.Id; process=$name; title=$title; reason=$_.Exception.Message }
  }
}

$remaining = @(Get-Process | Where-Object {
  $_.MainWindowHandle -ne 0 -and
  $_.MainWindowTitle -match '(?i)(Windows Terminal|PowerShell|Command Prompt|cmd.exe)'
} | Select-Object Id,ProcessName,MainWindowTitle)

$evidence = [ordered]@{
  nodeId='PC2'
  computerName=$env:COMPUTERNAME
  executed=$true
  executedAt=[DateTime]::UtcNow.ToString('o')
  closed=$closed
  skipped=$skipped
  remaining=$remaining
  verified=($remaining.Count -eq 0)
}
$dir='C:AX-Runtimeevidence'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$path=Join-Path $dir 'terminal-cleanup-latest.json'
$evidence | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8

if ($remaining.Count -ne 0) { throw "TERMINAL_CLEANUP_NOT_VERIFIED:$($remaining.Count)" }
Write-Host 'PC2_TERMINAL_CLEANUP=VERIFIED'
Write-Host "EVIDENCE=$path"
