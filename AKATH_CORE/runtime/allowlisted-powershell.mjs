import { spawn } from 'node:child_process';

const ACTIONS = Object.freeze({
  runtime_heartbeat: Object.freeze({
    script: 'Write-Output "AX_PC1_RUNTIME_HEARTBEAT"'
  }),
  runtime_status: Object.freeze({
    script: 'Write-Output "AX_PC1_RUNTIME_STATUS"'
  }),
  runtime_identity: Object.freeze({
    script: '$id=[ordered]@{computerName=$env:COMPUTERNAME;userName="$env:USERDOMAIN\\$env:USERNAME";nodeId=$env:AX_PC1_NODE_ID;processId=$PID;powershellVersion=$PSVersionTable.PSVersion.ToString()};$id|ConvertTo-Json -Compress'
  }),
  runtime_process_snapshot: Object.freeze({
    script: 'Get-Process | Where-Object { $_.ProcessName -match "node|powershell" } | Select-Object -First 20 Id,ProcessName | Format-Table -AutoSize | Out-String'
  }),
  runtime_disk_snapshot: Object.freeze({
    script: 'Get-PSDrive -PSProvider FileSystem | Select-Object Name,Free,Used | Format-Table -AutoSize | Out-String'
  }),
  jumtask: Object.freeze({
    script: '$out = if ($env:AX_PC2_JUMTASK_OUTPUT) { $env:AX_PC2_JUMTASK_OUTPUT } else { Join-Path $env:TEMP "AERIS_JUMTASK_OUTPUT.txt" }; Start-Sleep -Milliseconds 500; Write-Output "[JUMTASK] STEP=WORK"; Start-Sleep -Milliseconds 700; Write-Output "[JUMTASK] STEP=VERIFY"; Start-Sleep -Milliseconds 500; $record = "JUMTASK_OK|HOST=$env:COMPUTERNAME|USER=$env:USERNAME|UTC=$([DateTime]::UtcNow.ToString("o"))"; Set-Content -Path $out -Value $record -Encoding UTF8; Write-Output "[JUMTASK] OUTPUT=$out"; Write-Output "[JUMTASK] RESULT=JUMTASK_OK"'
  })
});

export function listAllowlistedActions() {
  return Object.keys(ACTIONS);
}

export async function executeAllowlistedPowerShell(action, { onStdout, onStderr } = {}) {
  const spec = ACTIONS[action];
  if (!spec) throw new Error(`PowerShell action not allowlisted: ${action}`);

  return new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', spec.script
    ], {
      shell: false,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => {
      const text = chunk.toString();
      stdout += text;
      onStdout?.(text);
    });
    child.stderr.on('data', chunk => {
      const text = chunk.toString();
      stderr += text;
      onStderr?.(text);
    });
    child.on('error', reject);
    child.on('close', exitCode => resolve({ action, stdout: stdout.trim(), stderr: stderr.trim(), exitCode }));
  });
}
