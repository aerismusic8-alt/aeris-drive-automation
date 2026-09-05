param(
  [string]$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'

# Build the legacy token without storing its literal spelling in this audit file.
$legacyToken = ([char]65) + ([char]69) + ([char]82) + ([char]73) + ([char]83)
$excludedNames = @('.git', 'node_modules', '.venv')
$excludedFiles = @('akath_legacy_identity_audit.ps1')
$activeIdentityPattern = '(?im)(?:company|organization|brand|system|service|project|identity)\s*[:=]\s*["''`]?\s*' + [regex]::Escape($legacyToken) + '\b|\bcurrent\s+(?:company|organization|brand|system|project|identity)\b[^\r\n]*\b' + [regex]::Escape($legacyToken) + '\b|\bactive\s+(?:company|organization|brand|system|project|identity)\b[^\r\n]*\b' + [regex]::Escape($legacyToken) + '\b'

$rootPath = [System.IO.Path]::GetFullPath($Root)
$matches = New-Object System.Collections.Generic.List[object]

Get-ChildItem -LiteralPath $rootPath -Recurse -Force -File -ErrorAction SilentlyContinue |
  Where-Object {
    $relative = $_.FullName.Substring($rootPath.Length).TrimStart('\\','/')
    $parts = $relative -split '[\\/]'
    ($parts | Where-Object { $excludedNames -contains $_ }).Count -eq 0 -and
    ($excludedFiles -notcontains $_.Name)
  } |
  ForEach-Object {
    try {
      $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 -ErrorAction Stop
      if ($content -match $activeIdentityPattern) {
        $matches.Add([pscustomobject]@{ path = $_.FullName.Substring($rootPath.Length).TrimStart('\\','/'); type = 'active-identity-declaration' })
      }
    } catch {
      # Ignore binary/unreadable files; the audit targets text/config artifacts.
    }
  }

if ($matches.Count -gt 0) {
  Write-Host 'AKATH LEGACY IDENTITY AUDIT: FAILED'
  $matches | Sort-Object path | Format-Table -AutoSize
  exit 2
}

Write-Host 'AKATH LEGACY IDENTITY AUDIT: PASSED'
Write-Host 'No active operating identity declaration uses the legacy identity token.'