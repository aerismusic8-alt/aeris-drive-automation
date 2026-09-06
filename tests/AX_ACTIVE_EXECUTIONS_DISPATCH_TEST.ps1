$ErrorActionPreference = 'Stop'

$workflowPath = Join-Path $PSScriptRoot '..\.github\workflows\ax-active-executions.yml'
$content = Get-Content -Raw -LiteralPath $workflowPath

if ($content -match 'gh api --method POST \$dispatchEndpoint --input -') {
  throw 'DISPATCH_STDIN_JSON_REGRESSION: workflow_dispatch must not pipe PowerShell JSON into gh api --input -'
}

if ($content -notmatch 'gh api --method POST \$dispatchEndpoint .* -f ref=main') {
  throw 'DISPATCH_FORM_ENCODING_MISSING: workflow_dispatch must use gh api -f fields'
}

if ($content -notmatch 'inputs\[target\]=\$target') {
  throw 'DISPATCH_TARGET_FIELD_MISSING'
}

if ($content -notmatch 'inputs\[task_id\]=') {
  throw 'DISPATCH_TASK_ID_FIELD_MISSING'
}

Write-Host 'AX_ACTIVE_EXECUTIONS_DISPATCH_TEST: PASS'
