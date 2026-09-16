import assert from 'node:assert/strict';
import { listSpecialists, resolveSpecialist } from './specialist-registry.mjs';

assert.deepEqual(listSpecialists(), [
  'PC1_MAIN_SPECIALIST',
  'PC1_SELF_CHECK_SPECIALIST',
  'PC1_RECOVERY_SPECIALIST'
]);

assert.equal(resolveSpecialist('execution').id, 'PC1_MAIN_SPECIALIST');
assert.equal(resolveSpecialist('self_check').id, 'PC1_SELF_CHECK_SPECIALIST');
assert.equal(resolveSpecialist('recovery').id, 'PC1_RECOVERY_SPECIALIST');
assert.equal(resolveSpecialist(undefined).id, 'PC1_MAIN_SPECIALIST');
assert.throws(() => resolveSpecialist('unknown_capability'), /Unknown specialist capability/);

console.log('PASS specialist registry');
