param(
  [string]$Path = "$env:USERPROFILE\\.aeris\\account-profile.json"
)
$dir = Split-Path -Parent $Path
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$email = Read-Host "Account email"
$username = Read-Host "Default username (optional)"
$displayName = Read-Host "Display name (optional)"
$fullName = Read-Host "Full name (optional)"
$password = Read-Host "Account password" -AsSecureString
$confirm = Read-Host "Confirm account password" -AsSecureString
$a=$password | ConvertFrom-SecureString
$b=$confirm | ConvertFrom-SecureString
if($a -ne $b){ throw "PASSWORD_CONFIRMATION_MISMATCH" }
$profile = [ordered]@{ version=1; email=$email; username=$username; display_name=$displayName; full_name=$fullName; password_dpapi=$a; created_at=(Get-Date).ToUniversalTime().ToString("o") }
$profile | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
icacls $Path /inheritance:r /grant:r "$env:USERNAME:(R,W)" | Out-Null
Write-Output "ACCOUNT_PROFILE_SAVED:$Path"