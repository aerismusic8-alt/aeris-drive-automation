import { spawn } from 'node:child_process';

const ACTIONS = Object.freeze({
  runtime_heartbeat: Object.freeze({
    script: 'Write-Output "AX_PC1_RUNTIME_HEARTBEAT"'
  }),
  runtime_identity: Object.freeze({
    script: '$PSVersionTable.PSVersion.ToString()'
  })
});

export function listAllowlistedActions() {
  return Object.keys(ACTIONS);
}

export async function executeAllowlistedPowerShell(action) {
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
    child.stdout.on('data', chunk => { stdout += chunk.toString(); });
    child.stderr.on('data', chunk => { stderr += chunk.toString(); });
    child.on('error', reject);
    child.on('close', exitCode => resolve({ action, stdout: stdout.trim(), stderr: stderr.trim(), exitCode }));
  });
}
