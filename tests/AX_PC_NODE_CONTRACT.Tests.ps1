$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$node = Get-Content -Raw (Join-Path $root 'AX_PC_CONTROL/AX_PC_NODE.ps1')

# Regression: plain text queue items must not be silently converted into
# terminal/admin commands. Operations must be explicit.
if ($node -match '\$args\.command=\[string\]\$Item\.content') {
  throw 'PC_NODE_PLAIN_TEXT_MUST_NOT_BECOME_COMMAND'
}
if ($node -notmatch 'OPERATION_REQUIRED') {
  throw 'PC_NODE_EXPLICIT_OPERATION_GUARD_MISSING'
}
if ($node -notmatch 'COMMAND_NOT_ALLOWED') {
  throw 'PC_NODE_ALLOWLIST_GATE_MISSING'
}
if ($node -notmatch 'terminal-powershell') {
  throw 'PC_NODE_TERMINAL_OPERATION_MISSING'
}

Write-Output 'AX_PC_NODE_CONTRACT_TESTS: PASS'
