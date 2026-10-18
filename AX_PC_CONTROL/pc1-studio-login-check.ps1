# PC1: is Studio signed in?
#
# Read-only and credential-blind. It reports the presence, names, sizes and
# timestamps of Roblox session files, plus auth-related log lines. It never
# reads, copies, prints or transmits a cookie, token or key value.

$ErrorActionPreference = 'Stop'
if ($env:COMPUTERNAME -ne 'DESKTOP-RGK6JKB') { throw "EXPECTED_PC1:$env:COMPUTERNAME" }

$local = 'C:\Users\User\AppData\Local\Roblox'
Write-Host "ROBLOX_LOCAL=$local"
Write-Host "ROBLOX_LOCAL_EXISTS=$(Test-Path -LiteralPath $local)"

# --- 1. LocalStorage (where a signed-in session is persisted) -------------
$lsRoot = Join-Path $local 'LocalStorage'
Write-Host "LOCALSTORAGE_EXISTS=$(Test-Path -LiteralPath $lsRoot)"
if (Test-Path -LiteralPath $lsRoot) {
  Get-ChildItem -LiteralPath $lsRoot -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("LS_ENTRY={0} DIR={1}" -f $_.Name, $_.PSIsContainer)
  }
}

# --- 2. Studio browser cookie store (presence only) -----------------------
$studioStore = Join-Path $lsRoot 'RobloxStudioBrowser'
Write-Host "STUDIO_STORE_EXISTS=$(Test-Path -LiteralPath $studioStore)"
if (Test-Path -LiteralPath $studioStore) {
  Get-ChildItem -LiteralPath $studioStore -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host ("STORE_FILE={0} BYTES={1} MTIME={2}" -f $_.Name, $_.Length, $_.LastWriteTimeUtc.ToString('o'))
  }
}

# --- 3. Any Roblox cookie DB anywhere in the profile (names/sizes only) ---
$found = @()
foreach ($pat in @('Cookies', 'Cookies-journal', '*.ldb', '*.log')) {
  $found += @(Get-ChildItem -LiteralPath $local -Recurse -Force -Filter $pat -ErrorAction SilentlyContinue |
    Select-Object -First 20)
}
foreach ($f in $found) {
  Write-Host ("SESSION_FILE={0} BYTES={1} MTIME={2}" -f $f.FullName, $f.Length, $f.LastWriteTimeUtc.ToString('o'))
}

# --- 4. Auth lines in the most recent Studio logs ------------------------
$logDir = Join-Path $local 'logs'
Write-Host "LOG_DIR_EXISTS=$(Test-Path -LiteralPath $logDir)"
if (Test-Path -LiteralPath $logDir) {
  $latest = Get-ChildItem -LiteralPath $logDir -Filter '*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 3
  foreach ($lg in $latest) {
    Write-Host ("--- LOG {0} ({1} bytes) ---" -f $lg.Name, $lg.Length)
    # Only lines whose subject is authentication. No value is printed, only the
    # line shape Roblox itself writes.
    Select-String -LiteralPath $lg.FullName -Pattern 'signin|sign-in|SignIn|logged in|Login|Authentication|WebAuthenticator|userId|UserId|GetUserId|not signed|SignedOut' -ErrorAction SilentlyContinue |
      Select-Object -First 25 | ForEach-Object {
        # Mask anything that looks like a credential before printing: these log
        # lines sit next to tokens and private keys.
        $shape = $_.Line.Trim() -replace '[A-Za-z0-9+/=_-]{24,}', '<redacted>'
        Write-Host ("AUTH_LINE: " + $shape)
      }
  }
}

Write-Host "LOGIN_CHECK=COMPLETE"
