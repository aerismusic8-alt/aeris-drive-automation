param([string]$Root='C:\AERIS\AX')
$ErrorActionPreference='Stop'
$now=(Get-Date).ToUniversalTime().ToString('o')
$dirs=@('00_CANONICAL_STATE','01_INBOX','02_WORK','03_MEDIA','04_SCRIPTS','05_LOGS','06_EVIDENCE','07_ARCHIVE','08_EMERGENCY_BACKUP','09_MANIFEST')
foreach($d in $dirs){New-Item -ItemType Directory -Force -Path (Join-Path $Root $d)|Out-Null}
$state=[ordered]@{schema='AX_CANONICAL_BOOTSTRAP_V1';updatedAt=$now;sourcePriority=@('Drive','PC1','PC2','GitHub');requiredState=@('AICS_MASTER_STATE','AERIS_MASTER_STATE','ARTIST_MASTER_REGISTRY','PROJECT_MASTER_REGISTRY','AX_SYSTEM_STATE');status='READY'}
$p=Join-Path $Root '00_CANONICAL_STATE\AX_CANONICAL_BOOTSTRAP.json'
$state|ConvertTo-Json -Depth 8|Set-Content $p -Encoding UTF8
$manifest=[ordered]@{schema='AX_STORAGE_MANIFEST_V1';updatedAt=$now;root=$Root;canonical=$p;retention=@{logsDays=7;evidenceDays=14;archiveDays=30;tempDays=1};protected=@('00_CANONICAL_STATE','04_SCRIPTS','08_EMERGENCY_BACKUP')}
$mp=Join-Path $Root '09_MANIFEST\AX_STORAGE_MANIFEST.json'
$manifest|ConvertTo-Json -Depth 8|Set-Content $mp -Encoding UTF8
$v=Get-Content -Raw $p|ConvertFrom-Json
if($v.schema -ne 'AX_CANONICAL_BOOTSTRAP_V1' -or $v.status -ne 'READY'){throw 'BOOTSTRAP_VERIFY_FAILED'}
Write-Host "AX_CANONICAL_BOOTSTRAP=VERIFIED root=$Root at=$now"
