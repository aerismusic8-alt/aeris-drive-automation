$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot '..'
$workflow=Get-Content -Raw (Join-Path $root '.github/workflows/ax-openai-dispatcher.yml')
$codeWorkflow=Get-Content -Raw (Join-Path $root '.github/workflows/ax-openai-live-code-stream.yml')

# Regression: the dispatcher must not pass GitHub CLI option tokens as the --jq expression.
if ($workflow -match '--jq\s+--argjson') {
  throw 'OPENAI_DISPATCHER_JQ_ARGUMENT_ORDER_INVALID'
}

# The dispatcher executes the READY task directly so it does not depend on nested workflow_dispatch permissions.
if ($workflow -match 'gh\s+workflow\s+run') {
  throw 'OPENAI_DISPATCHER_NESTED_WORKFLOW_DISPATCH_FORBIDDEN'
}
if ($workflow -notmatch 'ax_openai_code_writer\.py') {
  throw 'OPENAI_DISPATCHER_DIRECT_WORKER_MISSING'
}
if ($workflow -notmatch 'OPENAI_DISPATCH_CONFIRMED') {
  throw 'OPENAI_DISPATCH_CONFIRMED_MARKER_MISSING'
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
