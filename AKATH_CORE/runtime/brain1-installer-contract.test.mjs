import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(root, '..', '..');
const installer = await readFile(resolve(repoRoot, 'AX_PC_CONTROL', 'install-brain1-local-control.ps1'), 'utf8');

// Regression guard: the installer previously passed -LogonType InteractiveToken,
// which is not a member of the ScheduledTask LogonTypeEnum. Registration threw
// before any task was created, so the Brain1 bootstrap failed at
// INSTALL_EXIT:1 and no heartbeat was ever produced.
const VALID_LOGON_TYPES = ['None', 'Password', 'S4U', 'Interactive', 'Group', 'ServiceAccount', 'InteractiveOrPassword'];

test('installer uses a valid ScheduledTask LogonType', () => {
  const match = installer.match(/-LogonType\s+([A-Za-z]+)/);
  assert.ok(match, 'installer must specify -LogonType');
  assert.ok(
    VALID_LOGON_TYPES.includes(match[1]),
    `-LogonType ${match[1]} is not in the LogonTypeEnum (${VALID_LOGON_TYPES.join(', ')})`
  );
});

// Regression guard: the self-hosted runner executes as NT AUTHORITY\NETWORK
// SERVICE. Resolving the principal from WindowsIdentity::GetCurrent() would bind
// the -AtLogOn trigger to the service account, which never logs on interactively,
// so the tasks would register but never run.
test('installer resolves the interactive user rather than the service account', () => {
  assert.match(installer, /Get-CimInstance Win32_ComputerSystem\)\.UserName/);
  assert.doesNotMatch(
    installer,
    /WindowsIdentity\]::GetCurrent\(\)\.User\.Value/,
    'principal must not be derived from the runner service identity'
  );
  assert.match(installer, /New-ScheduledTaskTrigger -AtLogOn -User \$interactiveUser/);
});

// The evidence gate treats a written proof file as progress, so the installer
// must not record INSTALLED when registration failed.
test('installer records an honest install proof', () => {
  assert.match(installer, /status='PENDING'/);
  assert.match(installer, /status='FAILED'/);
  assert.match(installer, /status='INSTALLED'/);
  const failBranch = installer.slice(installer.indexOf("status='FAILED'"));
  assert.match(failBranch, /Set-Content .*brain1-install-proof\.json/);
  assert.match(failBranch, /throw/);
});

// The workers write heartbeats into C:\AX-Runtime, which the runner service
// account may have created. Without an explicit grant the interactive user
// cannot write evidence there.
test('installer grants the interactive account write access to the runtime root', () => {
  assert.match(installer, /AddAccessRule/);
  assert.match(installer, /FileSystemAccessRule\(\$sid,'Modify'/);
  assert.match(installer, /Set-Acl -Path \$root/);
});

console.log('PASS PC1 Brain1 installer contract');
