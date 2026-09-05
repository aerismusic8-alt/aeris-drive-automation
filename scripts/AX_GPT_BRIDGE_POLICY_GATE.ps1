$ErrorActionPreference = 'Stop'
$policyPath = Join-Path $env:GITHUB_WORKSPACE 'AX_GPT_BRIDGE_POLICY.json'
if (-not (Test-Path $policyPath)) { throw "AX_GPT_BRIDGE_POLICY_NOT_FOUND: $policyPath" }
$policy = Get-Content -Raw -Path $policyPath | ConvertFrom-Json
if ($policy.status -ne 'ACTIVE') {
  Write-Host "AX GPT bridge is $($policy.status); no temporary bridge execution will run."
  exit 78
}
if ($policy.independence_rule.chatgpt_is_control_channel_only -ne $true) { throw 'AX_GPT_BRIDGE_POLICY_INVALID_CONTROL_CHANNEL_RULE' }
if ($policy.independence_rule.chatgpt_availability_is_not_ax_execution_state -ne $true) { throw 'AX_GPT_BRIDGE_POLICY_INVALID_AVAILABILITY_RULE' }
if ($policy.independence_rule.trigger_must_not_call_chatgpt_to_make_progress -ne $true) { throw 'AX_GPT_BRIDGE_POLICY_INVALID_NO_CHATGPT_DEPENDENCY_RULE' }
if ($policy.command_safety.durable_command_id_required -ne $true -or $policy.command_safety.idempotency_required -ne $true) { throw 'AX_GPT_BRIDGE_POLICY_INVALID_COMMAND_GUARDS' }
if ($policy.command_safety.terminal_states_are_never_retriggered -ne $true) { throw 'AX_GPT_BRIDGE_POLICY_INVALID_TERMINAL_RETRIGGER_GUARD' }
if ($policy.financial_guard.financial_execution_enabled -ne $false) { throw 'AX_GPT_BRIDGE_POLICY_FINANCIAL_GUARD_INVALID' }
Write-Host 'AX GPT bridge policy: VERIFIED/ACTIVE'
Write-Host "Heartbeat: $($policy.wake_policy.heartbeat_minutes) minutes"
Write-Host "Max concurrent cycles: $($policy.wake_policy.max_concurrent_cycles)"
