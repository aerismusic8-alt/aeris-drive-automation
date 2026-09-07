const COMPLETE = new Set(['PASS', 'VERIFIED']);
const NEED_ACTION = new Set(['FAILED', 'BLOCKED', 'WAITING_K']);

function assertObject(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${name} must be an object`);
}
function isStale(timestamp, now = Date.now(), staleMs = 10_000) {
  const parsed = Date.parse(timestamp ?? '');
  return !Number.isFinite(parsed) || now - parsed > staleMs;
}
function normalizeTask(task) {
  return { id: task?.id ?? task?.taskId ?? null, status: task?.status ?? 'UNKNOWN', agent: task?.agent ?? task?.owner ?? null, action: task?.action ?? null, result: task?.result ?? null, verification: task?.verification ?? null, error: task?.error ?? null, retry: task?.retry ?? null, timestamp: task?.timestamp ?? task?.updatedAt ?? null };
}
function normalizeEvent(event) {
  return { id: event?.id ?? null, type: event?.type ?? 'UNKNOWN', message: event?.message ?? event?.text ?? null, status: event?.status ?? 'UNKNOWN', timestamp: event?.timestamp ?? event?.createdAt ?? null };
}
function normalizeAgent(agent) {
  return { id: agent?.id ?? agent?.name ?? null, name: agent?.name ?? agent?.id ?? 'UNKNOWN', status: agent?.status ?? 'UNKNOWN', role: agent?.role ?? null, route: agent?.route ?? agent?.execution ?? null, timestamp: agent?.timestamp ?? agent?.updatedAt ?? null };
}
function normalizeCodeStream(stream) {
  assertObject(stream, 'codeStream');
  if (stream.schema !== 'AX_CODE_STREAM_V1') throw new TypeError('AX_CODE_STREAM_V1 required');
  if (!Array.isArray(stream.lines)) throw new TypeError('codeStream.lines must be an array');
  return {
    schema: stream.schema,
    status: stream.status ?? 'UNKNOWN',
    agent: stream.agent ?? 'UNKNOWN',
    taskId: stream.taskId ?? null,
    file: stream.file ?? null,
    startedAt: stream.startedAt ?? null,
    updatedAt: stream.updatedAt ?? null,
    lines: stream.lines.map((line, index) => ({
      seq: Number.isFinite(Number(line?.seq)) ? Number(line.seq) : index + 1,
      kind: line?.kind ?? 'stdout',
      text: String(line?.text ?? '')
    }))
  };
}
function asArray(value, key) { if (value == null) return []; if (!Array.isArray(value)) throw new TypeError(`${key} must be an array`); return value; }
function countTaskStatuses(tasks) {
  const counts = { running: 0, queued: 0, failed: 0, completed: 0 };
  for (const task of asArray(tasks, 'tasks')) {
    const status = String(task?.status ?? 'UNKNOWN').toUpperCase();
    if (status.includes('RUNNING')) counts.running += 1;
    else if (status.includes('QUEUED')) counts.queued += 1;
    else if (NEED_ACTION.has(status)) counts.failed += 1;
    else if (status === 'COMPLETED' || status === 'DONE') counts.completed += 1;
  }
  return counts;
}
function normalizeDashboardState(status, sync, extras = {}, now = Date.now(), staleMs = 10_000) {
  assertObject(status, 'status');
  if (sync != null) assertObject(sync, 'sync');
  assertObject(extras, 'extras');
  const stages = [status.recovery, status.decision, status.dispatch, status.persistence];
  const completed = stages.filter(value => COMPLETE.has(String(value ?? '').toUpperCase())).length;
  return {
    system: { status: status.system ?? 'UNKNOWN', overall: status.overall ?? 'UNKNOWN', stale: isStale(status.timestamp ?? null, now, staleMs), timestamp: status.timestamp ?? null },
    pipeline: { recovery: status.recovery ?? 'UNKNOWN', decision: status.decision ?? 'UNKNOWN', dispatch: status.dispatch ?? 'UNKNOWN', persistence: status.persistence ?? 'UNKNOWN', progress: Math.round(completed / stages.length * 100) },
    sync: { schema: sync?.schema ?? null, timestamp: sync?.syncAt ?? null, sourceState: sync?.sourceState ?? null, verified: sync?.schema === 'AX_DASHBOARD_SYNC_V1' && sync?.stateVerified === true },
    selectedTask: status.selectedTask ?? status.taskId ?? null,
    tasks: asArray(extras.tasks, 'tasks').map(normalizeTask), events: asArray(extras.events, 'events').map(normalizeEvent), agents: asArray(extras.agents, 'agents').map(normalizeAgent),
    evidence: { runner: status.runner ?? 'UNKNOWN', mutation: status.mutation ?? 'UNKNOWN', cycle: status.cycle ?? null }
  };
}
export { isStale, normalizeTask, normalizeEvent, normalizeAgent, normalizeCodeStream, countTaskStatuses, normalizeDashboardState };
