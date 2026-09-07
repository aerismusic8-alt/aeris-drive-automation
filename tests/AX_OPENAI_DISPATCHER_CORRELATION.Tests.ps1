$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot '..'
$workflow=Get-Content -Raw (Join-Path $root '.github/workflows/ax-openai-dispatcher.yml')

# Regression: the dispatcher must not pass gh CLI option tokens as the --jq expression.
if ($workflow -match '--jq\s+--argjson') {
  throw 'OPENAI_DISPATCHER_JQ_ARGUMENT_ORDER_INVALID'
}

# Correlation must use a real jq expression and retain a polling fallback.
if ($workflow -notmatch '--json databaseId,createdAt\s+--jq\s+[''\"]\[\.\[0\]\.databaseId') {
  throw 'OPENAI_DISPATCHER_RUN_ID_LOOKUP_INVALID'
}
if ($workflow -notmatch 'OPENAI_WORKFLOW_RUN_ID_NOT_FOUND') {
  throw 'OPENAI_DISPATCHER_MISSING_RUN_ID_GUARD'
}

Write-Host 'AX_OPENAI_DISPATCHER_CORRELATION_TEST: PASS'
