import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyControl2Evidence } from './control-e2e-verifier.mjs';

const base = {
  node_id: 'DESKTOP-M9M4818',
  brain_heartbeat_at: '2026-09-25T03:46:51+07:00',
  control_heartbeat_at: '2026-09-25T03:46:45+07:00',
  captureFresh: true,
  brainVisionFresh: true,
  browser: true,
  auth: true,
  diagnosis: 'AUTHENTICATED_READY',
  next_action: 'OBSERVE_OFFER_BEFORE_ACTION',
  currentErrorStreak: 0,
  verification: 'READY'
};

test('control readiness requires fresh observation and healthy state', () => {
  const result = verifyControl2Evidence(base, Date.parse('2026-09-25T03:47:00+07:00'));
  assert.equal(result.controlReady, true);
  assert.equal(result.e2eVerified, false);
  assert.ok(result.e2eReasons.includes('no_control_action_executed'));
});

test('E2E requires action plus post-action evidence and verification', () => {
  const result = verifyControl2Evidence({
    ...base,
    action_executed: true,
    post_action_evidence: true,
    post_action_verified: true
  }, Date.parse('2026-09-25T03:47:00+07:00'));
  assert.equal(result.controlReady, true);
  assert.equal(result.e2eVerified, true);
});

test('stale Control heartbeat blocks readiness', () => {
  const result = verifyControl2Evidence(base, Date.parse('2026-09-25T03:48:00+07:00'));
  assert.equal(result.controlReady, false);
  assert.ok(result.readinessReasons.includes('control_heartbeat_stale'));
});
