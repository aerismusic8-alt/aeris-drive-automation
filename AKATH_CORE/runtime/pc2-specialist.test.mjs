import assert from 'node:assert/strict';
import { verifyExecutionResult } from './pc2-specialist-verifier.mjs';

const revenueStdout = '[REVENUE] OUTPUT=C:\\aeris\\AERIS_REVENUE_OUTPUT\\PC2-REV-YT-SHORT-1-1\r\n[REVENUE] RESULT=YOUTUBE_SHORT_PACKAGE_READY';
assert.equal(verifyExecutionResult('youtube_short_package', { exitCode: 0, stdout: revenueStdout }, 'PC2-MAIN'), true);
assert.equal(verifyExecutionResult('youtube_short_package', { exitCode: 1, stdout: revenueStdout }, 'PC2-MAIN'), false);
assert.equal(verifyExecutionResult('youtube_short_package', { exitCode: 0, stdout: '[REVENUE] OUTPUT=x' }, 'PC2-MAIN'), false);

const jumtaskStdout = 'JUMTASK_OK|HOST=DESKTOP|USER=pc2|UTC=2026-09-17T00:00:00Z';
assert.equal(verifyExecutionResult('jumtask', { exitCode: 0, stdout: jumtaskStdout }, 'PC2-MAIN'), true);

console.log('PASS PC2 specialist verification contract');
