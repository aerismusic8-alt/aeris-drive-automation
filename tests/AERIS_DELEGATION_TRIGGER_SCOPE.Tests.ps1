# AERIS Delegation Trigger scope regression
# Root cause: AERIS_DELEGATION_QUEUE_TRIGGER referenced `data` and `index`
# after AERIS_AUTONOMOUS_NEXT_ACTION(), where those variables are not in scope.
# This must never be allowed to pass as a trigger/runtime success.

$sourcePath = Join-Path $PSScriptRoot "..\AERIS_Code.gs"
$source = Get-Content -Raw -LiteralPath $sourcePath

if ($source -notmatch 'function\s+AERIS_DELEGATION_QUEUE_TRIGGER\s*\(\)') {
    throw 'TRIGGER_FUNCTION_NOT_FOUND'
}

$triggerStart = $source.IndexOf('function AERIS_DELEGATION_QUEUE_TRIGGER()')
$triggerEnd = $source.IndexOf('function INSTALL_AERIS_DELEGATION_TRIGGER()', $triggerStart)
if ($triggerStart -lt 0 -or $triggerEnd -lt 0) {
    throw 'TRIGGER_BOUNDARY_NOT_FOUND'
}

$trigger = $source.Substring($triggerStart, $triggerEnd - $triggerStart)

# The trigger may call autonomous routing, but it must not reference queue-local
# variables that are only defined inside AERIS_AUTONOMOUS_NEXT_ACTION().
if ($trigger -match '\bdata\b' -and $trigger -match '\bindex\b') {
    throw 'TRIGGER_SCOPE_REGRESSION: AERIS_DELEGATION_QUEUE_TRIGGER references out-of-scope data/index'
}

Write-Output 'AERIS_DELEGATION_TRIGGER_SCOPE_TEST: PASS'
