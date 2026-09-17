import assert from 'node:assert/strict';
import { executeControlTask, listAllowedControlActions } from './pc1-control.mjs';

assert.deepEqual(listAllowedControlActions(), ['pc1_status', 'runtime_status']);

let captured = null;
const result = await executeControlTask({
  task_id: 'PC1-CONTROL-TEST',
  capability: 'control',
  action: 'pc1_status'
}, {
  spawnImpl: (command, args) => {
    captured = { command, args };
    const listeners = {};
    const child = {
      stdout: { on: (event, handler) => { listeners[`stdout:${event}`] = handler; } },
      stderr: { on: (event, handler) => { listeners[`stderr:${event}`] = handler; } },
      on: (event, handler) => { listeners[event] = handler; },
      kill: () => {}
    };
    queueMicrotask(() => {
      listeners['stdout:data']?.({ toString: () => '7.5.0' });
      listeners.close?.(0);
    });
    return child;
  },
  timeoutMs: 1000
});

assert.equal(captured.command, 'powershell.exe');
assert.deepEqual(captured.args.slice(0, 4), ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass']);
assert.equal(result.action, 'pc1_status');
assert.equal(result.exitCode, 0);
assert.equal(result.stdout, '7.5.0');

await assert.rejects(
  () => executeControlTask({ capability: 'control', action: 'arbitrary_powershell' }),
  /not allowlisted/
);

console.log('PASS PC1 control bridge');
