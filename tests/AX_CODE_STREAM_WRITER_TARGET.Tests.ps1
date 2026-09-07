$ErrorActionPreference='Stop'
$writer=Get-Content -Raw (Join-Path $PSScriptRoot '..\AKATH\runtime\ax_code_stream_writer.ps1')
if(-not $writer.Contains('$targetPath=Join-Path $root $File') -and -not $writer.Contains('Set-Content -LiteralPath $targetPath')){
  throw 'AX_CODE_STREAM_TARGET_WRITE_MISSING'
}
if(-not $writer.Contains('if($Event -eq ''START'')') -or -not $writer.Contains('if($Event -eq ''LINE'')') -or -not $writer.Contains('if($Event -eq ''ERROR'')')){
  throw 'AX_CODE_STREAM_EVENT_PATH_MISSING'
}
Write-Host 'AX_CODE_STREAM_WRITER_TARGET_TEST: PASS'