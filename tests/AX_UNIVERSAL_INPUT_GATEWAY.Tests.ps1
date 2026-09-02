$ErrorActionPreference = 'Stop'

$gateway = Get-Content "$PSScriptRoot/../AX_UNIVERSAL_INPUT_GATEWAY.gs" -Raw

if ($gateway -notmatch 'AX_UNIVERSAL_INPUT_GATEWAY') { throw 'GATEWAY_NAME_MISSING' }
if ($gateway -notmatch 'CHATGPT_UPLOAD_NOT_REQUIRED') { throw 'CHATGPT_UPLOAD_MUST_NOT_BE_REQUIRED' }
if ($gateway -notmatch 'GOOGLE_DRIVE') { throw 'GOOGLE_DRIVE_SOURCE_MISSING' }
if ($gateway -notmatch 'AERIS_DRIVE') { throw 'AERIS_DRIVE_SOURCE_MISSING' }
if ($gateway -notmatch 'GITHUB') { throw 'GITHUB_SOURCE_MISSING' }
if ($gateway -notmatch 'retrieved !== true') { throw 'RETRIEVAL_GATE_MISSING' }
if ($gateway -notmatch 'contentHash') { throw 'CONTENT_HASH_GATE_MISSING' }
if ($gateway -notmatch 'INPUT_RETRIEVAL_VERIFIED') { throw 'VERIFICATION_STATE_MISSING' }

Write-Host 'AX_UNIVERSAL_INPUT_GATEWAY_TESTS: PASS'
