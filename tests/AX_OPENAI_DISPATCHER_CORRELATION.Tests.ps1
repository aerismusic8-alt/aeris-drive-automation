$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot '..'
$workflow=Get-Content -Raw (Join-Path $root '.github/workflows/ax-openai-dispatcher.yml')
$codeWorkflow=Get-Content -Raw (Join-Path $root '.github/workflows/ax-openai-live-code-stream.yml')

# Regression: the dispatcher must not pass GitHub CLI option tokens as the --jq expression.
if ($workflow -match '--jq\s+--argjson') {
  throw 'OPENAI_DISPATCHER_JQ_ARGUMENT_ORDER_INVALID'
}

# Correlation must use a quoted jq expression that extracts the latest workflow-dispatch run ID.
if ($workflow -notmatch "--json\s+databaseId\s+--jq\s+'[^']*databaseId[^']*'") {
  throw 'OPENAI_DISPATCHER_RUN_ID_LOOKUP_INVALID'
}
if ($workflow -notmatch 'OPENAI_WORKFLOW_RUN_ID_NOT_FOUND') {
  throw 'OPENAI_DISPATCHER_MISSING_RUN_ID_GUARD'
}

# A successful code-stream run must persist the generated file back to main, not only modify the ephemeral runner workspace.
if ($codeWorkflow -notmatch 'contents:\s*write') {
  throw 'OPENAI_CODE_STREAM_WRITEBACK_PERMISSION_MISSING'
}
if ($codeWorkflow -notmatch 'git\s+add\s+.*TARGET_FILE') {
  throw 'OPENAI_CODE_STREAM_WRITEBACK_GIT_ADD_MISSING'
}
if ($codeWorkflow -notmatch 'git\s+push\s+origin\s+HEAD:main') {
  throw 'OPENAI_CODE_STREAM_WRITEBACK_GIT_PUSH_MISSING'
}

Write-Host 'AX_OPENAI_DISPATCHER_CORRELATION_TEST: PASS'
