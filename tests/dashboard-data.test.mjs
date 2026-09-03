import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { normalizeDashboardState, countTaskStatuses } from '../dashboard/dashboard-data.mjs';

const baseStatus = {
  system: 'ONLINE', overall: 'PASS', recovery: 'PASS', decision: 'PASS', dispatch: 'PASS',
  persistence: 'VERIFIED', runner: 'VERIFIED', mutation: 'ENABLED',
  selectedTask: 'AX-RECOVERED-005', timestamp: '2026-09-03T10:13:12.348Z'
};
const verifiedSync = {
  schema: 'AX_DASHBOARD_SYNC_V1', syncAt: '2026-09-03T10:13:10.000Z',
  sourceState: 'dashboard/status.json', stateVerified: true
};

test('normalizes verified executive state and computes full pipeline progress', () => {
  const result = normalizeDashboardState(baseStatus, verifiedSync, {}, Date.parse('2026-09-03T10:13:13.000Z'), 10000);
  assert.equal(result.system.status, 'ONLINE');
  assert.equal(result.pipeline.progress, 100);
  assert.equal(result.selectedTask, 'AX-RECOVERED-005');
  assert.equal(result.sync.verified, true);
});

test('does not invent queue, activity, or agent records when sources are absent', () => {
  const result = normalizeDashboardState(baseStatus, verifiedSync, {}, Date.parse('2026-09-03T10:13:13.000Z'), 10000);
  assert.deepEqual(result.tasks, []);
  assert.deepEqual(result.events, []);
  assert.deepEqual(result.agents, []);
});

test('marks old source data stale', () => {
  const result = normalizeDashboardState(baseStatus, verifiedSync, {}, Date.parse('2026-09-03T10:14:00.000Z'), 10000);
  assert.equal(result.system.stale, true);
});

test('requires the exact sync schema and verification flag', () => {
  const result = normalizeDashboardState(baseStatus, { ...verifiedSync, schema: 'WRONG' }, {}, Date.parse('2026-09-03T10:13:13.000Z'), 10000);
  assert.equal(result.sync.verified, false);
});

test('rejects malformed dashboard state instead of fabricating status', () => {
  assert.throws(
    () => normalizeDashboardState(null, verifiedSync, {}, Date.parse('2026-09-03T10:13:13.000Z'), 10000),
    /status must be an object/
  );
});

test('dashboard HTML contains the mobile operations hub contract', () => {
  const html = fs.readFileSync(new URL('../dashboard/index.html', import.meta.url), 'utf8');
  for (const id of ['taskQueue', 'activityFeed', 'taskDetail', 'agentStatus', 'syncState', 'staleState']) {
    assert.match(html, new RegExp(`id=["']${id}["']`));
  }
});

test('classifies BLOCKED and WAITING_K as need-action tasks', () => {
  assert.deepEqual(countTaskStatuses([
    {status:'RUNNING'}, {status:'QUEUED'}, {status:'REPROCESS_QUEUED'},
    {status:'BLOCKED'}, {status:'WAITING_K'}, {status:'COMPLETED'}, {status:'FAILED'}
  ]), {running:1, queued:2, failed:3, completed:1});
});
