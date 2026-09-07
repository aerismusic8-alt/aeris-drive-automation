$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot '..'
$workflow=Get-Content -Raw (Join-Path $root '.github/workflows/ax-openai-dispatcher.yml')
$codeWorkflow=Get-Content -Raw (Join-Path $root '.github/workflows/ax-openai-live-code-stream.yml')

if ($workflow -match '--jq\s+--argjson') { throw 'OPENAI_DISPATCHER_JQ_ARGUMENT_ORDER_INVALID' }
if ($workflow -notmatch 'ax_openai_code_writer\.py') { throw 'OPENAI_DISPATCHER_DIRECT_WORKER_MISSING' }
if ($workflow -notmatch 'OPENAI_DISPATCH_CONFIRMED') { throw 'OPENAI_DISPATCH_CONFIRMED_MARKER_MISSING' }
if ($codeWorkflow -notmatch 'contents:\s*write') { throw 'OPENAI_CODE_STREAM_WRITEBACK_PERMISSION_MISSING' }
if ($codeWorkflow -notmatch 'git\s+add\s+.*TARGET_FILE') { throw 'OPENAI_CODE_STREAM_WRITEBACK_GIT_ADD_MISSING' }
if ($codeWorkflow -notmatch 'git\s+push\s+origin\s+HEAD:main') { throw 'OPENAI_CODE_STREAM_WRITEBACK_GIT_PUSH_MISSING' }
if ($codeWorkflow -notmatch 'PROMPT_FILE') { throw 'OPENAI_MULTILINE_PROMPT_FILE_HANDOFF_MISSING' }
if ($codeWorkflow -match '"PROMPT=\$prompt"\s*\|\s*Out-File\s+-FilePath\s+\$env:GITHUB_ENV') { throw 'OPENAI_MULTILINE_PROMPT_ENV_HANDOFF_FORBIDDEN' }
Write-Host 'AX_OPENAI_DISPATCHER_CORRELATION_TEST: PASS'
