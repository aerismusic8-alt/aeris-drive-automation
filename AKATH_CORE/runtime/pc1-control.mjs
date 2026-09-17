import { spawn } from 'node:child_process';

const ALLOWED_ACTIONS = Object.freeze({
  pc1_status: Object.freeze({
    script: '$PSVersionTable.PSVersion.ToString()'
  }),
  runtime_status: Object.freeze({
    script: 'Get-Date -Format o; Get-Process node -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Id'
  })
});

export function listAllowedControlActions() {
  return Object.keys(ALLOWED_ACTIONS);
}

export async function executeControlTask(job, {
  spawnImpl = spawn,
  powershell = process.env.AX_POWERSHELL || 'powershell.exe',
  timeoutMs = Number(process.env.AX_CONTROL_TIMEOUT_MS || 10000)
} = {}) {
  const action = job?.action || job?.payload?.action;
  const definition = ALLOWED_ACTIONS[action];
  if (!definition) {
    throw new Error(`Control action is not allowlisted: ${action || 'missing'}`);
  }

  return new Promise((resolve, reject) => {
    const child = spawnImpl(powershell, [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      definition.script
    ], { shell: false, stdio: ['ignore', 'pipe', 'pipe'] });

    let stdout = '';
    let stderr = '';
    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn(value);
    };
    const timer = setTimeout(() => {
      child.kill();
      finish(reject, new Error(`PowerShell control timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    child.stdout.on('data', (data) => { stdout += data; });
    child.stderr.on('data', (data) => { stderr += data; });
    child.on('error', (error) => finish(reject, error));
    child.on('close', (code) => {
      if (code !== 0) {
        finish(reject, new Error(`PowerShell exited ${code}: ${stderr.trim()}`));
        return;
      }
      finish(resolve, {
        action,
        command: definition.script,
        exitCode: code,
        stdout: stdout.trim(),
        stderr: stderr.trim()
      });
    });
  });
}
