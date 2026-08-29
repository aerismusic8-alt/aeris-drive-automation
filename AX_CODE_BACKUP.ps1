param(
  [string]$SourceRoot = "$PSScriptRoot",
  [string]$BackupRoot = 'C:\AERIS\AX\08_EMERGENCY_BACKUP\CODE',
  [string[]]$Extensions = @('.ps1','.psm1','.psd1','.gs','.js','.ts','.py','.json','.yml','.yaml','.cmd','.bat','.ini','.toml')
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
$stamp=(Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss_fff')
$manifest=@()
Get-ChildItem $SourceRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $Extensions -contains $_.Extension.ToLower() -and $_.FullName -notmatch '\\08_EMERGENCY_BACKUP\\' } |
  ForEach-Object {
    $rel=$_.FullName.Substring($SourceRoot.TrimEnd('\').Length).TrimStart('\')
    $dest=Join-Path $BackupRoot (Join-Path $stamp $rel)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $_.FullName $dest -Force
    $hash=(Get-FileHash $_.FullName -Algorithm SHA256).Hash
    $manifest += [pscustomobject]@{file=$rel;sourceHash=$hash;backup=$dest;timestampUtc=[DateTime]::UtcNow.ToString('o')}
  }
$mp=Join-Path $BackupRoot "$stamp.manifest.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content $mp -Encoding UTF8
$check=Get-Content -Raw $mp | ConvertFrom-Json
if(@($check).Count -lt 0){throw 'CODE_BACKUP_VERIFY_FAILED'}
Write-Host "AX_CODE_BACKUP=VERIFIED files=$(@($manifest).Count) path=$BackupRoot"
