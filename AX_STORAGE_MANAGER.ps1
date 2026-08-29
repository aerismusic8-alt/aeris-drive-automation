param([string]$Root='C:\AERIS\AX')
$ErrorActionPreference='Stop'
$dirs=@('00_CANONICAL_STATE','01_INBOX','02_WORK','03_MEDIA','04_SCRIPTS','05_LOGS','06_EVIDENCE','07_ARCHIVE','08_EMERGENCY_BACKUP','09_MANIFEST')
foreach($d in $dirs){New-Item -ItemType Directory -Force -Path (Join-Path $Root $d)|Out-Null}
$now=(Get-Date).ToUniversalTime().ToString('o')
$manifest=[ordered]@{schema='AX_STORAGE_MANIFEST_V1';updatedAt=$now;root=$Root;retention=@{logsDays=7;evidenceDays=14;archiveDays=30;tempDays=1};protected=@('00_CANONICAL_STATE','04_SCRIPTS','08_EMERGENCY_BACKUP');directories=$dirs}
$p=Join-Path $Root '09_MANIFEST\storage-manifest.json'
$manifest|ConvertTo-Json -Depth 8|Set-Content $p -Encoding UTF8
$verify=Get-Content -Raw $p|ConvertFrom-Json
if($verify.schema -ne 'AX_STORAGE_MANIFEST_V1'){throw 'STORAGE_MANIFEST_VERIFY_FAILED'}
Write-Host 'AX_STORAGE_LAYOUT=VERIFIED'
Write-Host "AX_STORAGE_ROOT=$Root"
Write-Host "AX_STORAGE_DIR_COUNT=$($dirs.Count)"
