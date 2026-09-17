export function verifyExecutionResult(action, ps, nodeId) {
  if (!ps || ps.exitCode !== 0) return false;
  const stdout = ps.stdout ?? '';
  if (action === 'jumtask') return /JUMTASK_OK/.test(stdout);
  if (action === 'youtube_short_package') {
    return /\[REVENUE\] MP4=\S+\.mp4/.test(stdout) &&
      /\[REVENUE\] BYTES=\d+/.test(stdout) &&
      /\[REVENUE\] OUTPUT=\S+/.test(stdout) &&
      /\[REVENUE\] RESULT=YOUTUBE_SHORT_PACKAGE_READY/.test(stdout);
  }
  if (action === 'runtime_identity') {
    try {
      const identity = JSON.parse(stdout);
      return !!identity?.computerName && (!identity?.nodeId || identity.nodeId === nodeId);
    } catch {
      return false;
    }
  }
  return true;
}
