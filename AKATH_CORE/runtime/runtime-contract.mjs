export function validateRuntimeState(state) {
  const required = ['runtimeStatus','nodeId','lastHeartbeatAt'];
  const missing = required.filter((key) => !state?.[key]);
  return { valid: missing.length === 0, missing };
}

export function validateEvidence(record) {
  const required = ['jobId','event','verification'];
  const missing = required.filter((key) => record?.[key] === undefined || record?.[key] === null);
  return { valid: missing.length === 0, missing };
}
