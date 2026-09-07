$ErrorActionPreference='Stop'
$writer=Get-Content -Raw (Join-Path $PSScriptRoot '..\AKATH\runtime\ax_code_stream_writer.ps1')
if($writer -notmatch "Join-Path \$root \$File" -and $writer -notmatch 'Set-Content.*\$File'){
  throw 'AX_CODE_STREAM_TARGET_WRITE_MISSING'
}
if($writer -notmatch "Event -eq 'START'" -or $writer -notmatch "Event -in @\('LINE','ERROR'\)"){
  throw 'AX_CODE_STREAM_EVENT_PATH_MISSING'
}
Write-Host 'AX_CODE_STREAM_WRITER_TARGET_TEST: PASS'