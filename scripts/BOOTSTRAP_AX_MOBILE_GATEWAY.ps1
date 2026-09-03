$ErrorActionPreference = 'Stop'

# Bootstrap only. This script never prints or commits the secrets.
$mobileBytes = New-Object byte[] 32
$pcBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($mobileBytes)
[Security.Cryptography.RandomNumberGenerator]::Fill($pcBytes)
$mobileSecret = [Convert]::ToBase64String($mobileBytes)
$pcSecret = [Convert]::ToBase64String($pcBytes)

$workerName = 'ax-control-runtime'
$runtimeUrl = 'https://ax-control-runtime.aerismusic8.workers.dev'

if ([string]::IsNullOrWhiteSpace($env:CLOUDFLARE_API_TOKEN)) {
    throw 'CLOUDFLARE_API_TOKEN environment variable is required for secret provisioning.'
}

Write-Host 'Provisioning AX Mobile Gateway secret...'
$mobileSecret | npx wrangler@latest secret put AX_MOBILE_INGRESS_SECRET --name $workerName
if ($LASTEXITCODE -ne 0) { throw 'AX_MOBILE_INGRESS_SECRET_PROVISION_FAILED' }

Write-Host 'Provisioning AX PC Pull secret...'
$pcSecret | npx wrangler@latest secret put AX_PC_PULL_SECRET --name $workerName
if ($LASTEXITCODE -ne 0) { throw 'AX_PC_PULL_SECRET_PROVISION_FAILED' }

[Environment]::SetEnvironmentVariable('AX_PC_PULL_SECRET', $pcSecret, 'User')

Write-Host ''
Write-Host 'AX Mobile Gateway bootstrap complete.'
Write-Host "Mobile URL: $runtimeUrl/mobile"
Write-Host 'Mobile token (store securely; do not commit):'
Write-Host $mobileSecret
Write-Host ''
Write-Host 'PC pull secret was installed as the current Windows-user environment variable AX_PC_PULL_SECRET.'
Write-Host 'The gateway remains FREE_ONLY and does not enable live financial execution.'
