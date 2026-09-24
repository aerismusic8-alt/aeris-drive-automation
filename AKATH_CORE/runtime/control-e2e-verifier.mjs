export function verifyControl2Evidence(bundle, nowMs = Date.now()) {
  const reasons = [];
  const required = [
    ['node_id', bundle?.node_id],
    ['brain_heartbeat_at', bundle?.brain_heartbeat_at],
    ['control_heartbeat_at', bundle?.control_heartbeat_at],
    ['diagnosis', bundle?.diagnosis],
    ['next_action', bundle?.next_action]
  ];

  for (const [name, value] of required) {
    if (value === undefined || value === null || value === '') reasons.push(`missing_${name}`);
  }

  if (bundle?.captureFresh !== true) reasons.push('capture_not_fresh');
  if (bundle?.brainVisionFresh !== true) reasons.push('brain_vision_not_fresh');
  if (bundle?.browser !== true) reasons.push('browser_not_ready');
  if (bundle?.auth !== true) reasons.push('auth_not_ready');
  if (bundle?.currentErrorStreak !== 0) reasons.push('error_streak_nonzero');
  if (bundle?.verification !== 'READY') reasons.push('verification_not_ready');

  const heartbeatMs = Date.parse(bundle?.control_heartbeat_at ?? '');
  if (!Number.isFinite(heartbeatMs)) reasons.push('invalid_control_heartbeat');
  else if (nowMs - heartbeatMs > 30_000) reasons.push('control_heartbeat_stale');

  const ready = reasons.length === 0;
  const actionExecuted = bundle?.action_executed === true;
  const postActionEvidence = bundle?.post_action_evidence === true;
  const postActionVerified = bundle?.post_action_verified === true;

  const e2eReasons = [...reasons];
  if (!actionExecuted) e2eReasons.push('no_control_action_executed');
  if (!postActionEvidence) e2eReasons.push('missing_post_action_evidence');
  if (!postActionVerified) e2eReasons.push('post_action_not_verified');

  return {
    controlReady: ready,
    e2eVerified: ready && e2eReasons.length === 0,
    readinessReasons: reasons,
    e2eReasons
  };
}
