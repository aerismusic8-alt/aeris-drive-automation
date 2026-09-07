$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$workflow = Get-Content -Raw "$root/.github/workflows/ax-gemini-live-code-stream.yml"
$helper = Get-Content -Raw "$root/AKATH/runtime/ax_gemini_helper.py"

if ($workflow -notmatch "push:\s*\r?\n\s*branches:\s*\[main\]") { throw 'GEMINI_PUSH_TRIGGER_MISSING' }
if ($workflow -notmatch "AX_MULTI_AI_DISPATCH_QUEUE\.json") { throw 'GEMINI_QUEUE_TRIGGER_MISSING' }
if ($workflow -notmatch 'contents:\s*write') { throw 'GEMINI_WRITE_PERMISSION_MISSING' }
if ($workflow -notmatch 'GEMINI_API_KEY') { throw 'GEMINI_SECRET_WIRING_MISSING' }
if ($workflow -notmatch 'git\s+push\s+origin\s+HEAD:main') { throw 'GEMINI_WRITEBACK_MISSING' }
if ($workflow -notmatch 'AX_GEMINI_CODE_STREAM_PASS') { throw 'GEMINI_PASS_EVIDENCE_MISSING' }
if ($helper -notmatch 'GEMINI_API_KEY_MISSING') { throw 'GEMINI_FAIL_CLOSED_GUARD_MISSING' }
Write-Host 'AX_GEMINI_EXECUTION_CONTRACT_TEST: PASS'
