const COMPLETE = new Set(['PASS', 'VERIFIED']);

function assertObject(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object`);
  }
}

function isStale(timestamp, now = Date.now(), staleMs = 10_000) {
  const parsed = Date.parse(timestamp ?? '');
  return !Number.isFinite(parsed) || now - parsed > staleMs;
}

function normalizeTask(task) {
  return {
    id: task?.id ?? task?.taskId ?? null,
    status: task?.status ?? 'UNKNOWN',
    agent: task?.agent ?? task?.owner ?? null,
    action: task?.action ?? null,
    result: task?.result ?? null,
    verification: task?.verification ?? null,
    error: task?.error ?? null,
    retry: task?.retry ?? null,
    timestamp: task?.timestamp ?? task?.updatedAt ?? null
  };
}

function normalizeEvent(event) {
  return {
    id: event?.id ?? null,
    type: event?.type ?? 'UNKNOWN',
    message: event?.message ?? event?.text ?? null,
    status: event?.status ?? 'UNKNOWN',
    timestamp: event?.timestamp ?? event?.createdAt ?? null
  };
}

function normalizeAgent(agent) {
  return {
    id: agent?.id ?? agent?.name ?? null,
    name: agent?.name ?? agent?.id ?? 'UNKNOWN',
    status: agent?.status ?? 'UNKNOWN',
    role: agent?.role ?? null,
    route: agent?.route ?? agent?.execution ?? null,
    timestamp: agent?.timestamp ?? agent?.updatedAt ?? null
  };
}

function asArray(value, key) {
  if (value == null) return [];
  if (!Array.isArray(value)) throw new TypeError(`${key} must be an array`);
  return value;
}

function normalizeDashboardState(status, sync, extras = {}, now = Date.now(), staleMs = 10_000) {
  assertObject(status, 'status');
  if (sync != null) assertObject(sync, 'sync');
  assertObject(extras, 'extras');

  const stages = [status.recovery, status.decision, status.dispatch, status.persistence];
  const completed = stages.filter(value => COMPLETE.has(String(value ?? '').toUpperCase())).length;
  const timestamp = status.timestamp ?? null;
  const stale = isStale(timestamp, now, staleMs);

  return {
    system: {
      status: status.system ?? 'UNKNOWN',
      overall: status.overall ?? 'UNKNOWN',
      stale,
      timestamp
    },
    pipeline: {
      recovery: status.recovery ?? 'UNKNOWN',
      decision: status.decision ?? 'UNKNOWN',
      dispatch: status.dispatch ?? 'UNKNOWN',
      persistence: status.persistence ?? 'UNKNOWN',
      progress: Math.round(completed / stages.length * 100)
    },
    sync: {
      schema: sync?.schema ?? null,
      timestamp: sync?.syncAt ?? null,
      sourceState: sync?.sourceState ?? null,
      verified: sync?.schema === 'AX_DASHBOARD_SYNC_V1' && sync?.stateVerified === true
    },
    selectedTask: status.selectedTask ?? status.taskId ?? null,
    tasks: asArray(extras.tasks, 'tasks').map(normalizeTask),
    events: asArray(extras.events, 'events').map(normalizeEvent),
    agents: asArray(extras.agents, 'agents').map(normalizeAgent),
    evidence: {
      runner: status.runner ?? 'UNKNOWN',
      mutation: status.mutation ?? 'UNKNOWN',
      cycle: status.cycle ?? null
    }
  };
}

export { isStale, normalizeTask, normalizeEvent, normalizeAgent, normalizeDashboardState };
