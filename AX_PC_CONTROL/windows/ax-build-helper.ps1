# Compile ax-helper.cs into ax-helper.dll once.
#
# Doing this on every call was the reason a script took minutes: csc start-up and
# the scan of the fresh assembly dominate. Once the DLL exists, Add-Type -Path
# loads it in milliseconds and every later script is fast.
$ErrorActionPreference = 'Continue'
$dir = 'C:\AX-Runtime\evidence'
$b64Path = Join-Path $dir 'ax-helper.cs.b64'
$cs = Join-Path $dir 'ax-helper.cs'
$dll = Join-Path $dir 'ax-helper.dll'

Write-Output "DECODING $b64Path"
$b64 = (Get-Content $b64Path -Raw) -replace '[^A-Za-z0-9+/=]', ''
[IO.File]::WriteAllBytes($cs, [Convert]::FromBase64String($b64))
Write-Output ("CS_BYTES=" + (Get-Item $cs).Length)

$csc = @(
  "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
  "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { Write-Output 'NO_CSC'; exit 1 }
Write-Output "CSC=$csc"

if (Test-Path $dll) { Remove-Item $dll -Force }

# Referencing the framework assemblies by full path avoids needing an SDK or a
# project file; csc is present on every Windows install.
$refs = @(
  "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\System.Drawing.dll",
  "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\System.Windows.Forms.dll"
) | Where-Object { Test-Path $_ }

$cargs = @('/nologo', '/target:library', "/out:$dll")
foreach ($r in $refs) { $cargs += "/reference:$r" }
$cargs += $cs

$sw = [Diagnostics.Stopwatch]::StartNew()
$out = & $csc @cargs 2>&1 | Out-String
Write-Output ("CSC_MS=" + $sw.ElapsedMilliseconds)
if ($out.Trim()) { Write-Output "CSC_OUT:"; Write-Output $out }

if (Test-Path $dll) {
  Write-Output ("DLL_OK=" + (Get-Item $dll).Length + " bytes")
} else {
  Write-Output 'DLL_MISSING'
  exit 1
}
