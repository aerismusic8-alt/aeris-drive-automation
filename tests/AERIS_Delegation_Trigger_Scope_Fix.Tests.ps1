$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot '..' 'AERIS_Delegation_Trigger_Scope_Fix.gs'
$source = Get-Content -Raw $path

if ($source -notmatch 'var data\s*=') { throw 'SCOPE_FIX_DATA_DECLARATION_MISSING' }
if ($source -notmatch 'var index\s*=') { throw 'SCOPE_FIX_INDEX_DECLARATION_MISSING' }
if ($source -notmatch 'SpreadsheetApp\.openById\(') { throw 'SCOPE_FIX_STABLE_SPREADSHEET_ACCESS_MISSING' }
if ($source -notmatch 'AERIS_DELEGATION_QUEUE') { throw 'SCOPE_FIX_QUEUE_SHEET_REFERENCE_MISSING' }
if ($source -notmatch 'verifyAERISDelegationTriggerScopeFix') { throw 'SCOPE_FIX_VERIFIER_MISSING' }

Write-Output 'AERIS_DELEGATION_TRIGGER_SCOPE_FIX_STATIC_TEST: PASS'
