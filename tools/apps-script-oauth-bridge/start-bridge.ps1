$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not $env:GOOGLE_OAUTH_CLIENT_ID) {
  throw 'GOOGLE_OAUTH_CLIENT_ID_REQUIRED'
}

node .\src\server.mjs
