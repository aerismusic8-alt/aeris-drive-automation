type AxEvent = {
  id: string;
  taskId: string;
  domain: string;
  priority: number;
  action: string;
  createdAt: string;
  source: string;
};

type AxBusinessEvidence = {
  taskId: string;
  [key: string]: unknown;
};

type AxExecutionResult = {
  accepted?: boolean;
  executed?: boolean;
  verified?: boolean;
  taskId?: string;
  evidence?: AxBusinessEvidence | null;
  writeBackVerified?: boolean;
  status?: string;
  [key: string]: unknown;
};

type Env = {
  AX_EXECUTION_QUEUE: Queue<AxEvent>;
};

const SERVICE = 'AX CONTROL RUNTIME';
const MODE = 'FREE_ONLY';
const QUEUE_NAME = 'ax-execution-events';
const REPO = 'aerismusic8-alt/aeris-drive-automation';
const MAX_PAYLOAD_BYTES = 16_000;

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

async function verifyGitHubToken(token: string): Promise<boolean> {
  try {
    const response = await fetch(`https://api.github.com/repos/${REPO}`, {
      method: 'GET',
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2026-03-10',
        'User-Agent': 'AX-AERIS-Control-Runtime',
      },
    });
    return response.ok;
  } catch {
    return false;
  }
}

function cloudTimeResponse(request: Request): Response {
  const now = new Date();
  const requestId = crypto.randomUUID();
  return json({
    source: 'AX_CLOUD_TIME_AUTHORITY',
    authority: 'Cloudflare Worker runtime',
    requestId,
    timestampUtc: now.toISOString(),
    epochMs: now.getTime(),
    timezoneDisplay: 'Asia/Bangkok',
    timestampThailand: now.toLocaleString('sv-SE', { timeZone: 'Asia/Bangkok' }).replace(' ', 'T') + '+07:00',
    method: request.method,
  });
}

function healthResponse(): Response {
  return json({
    service: SERVICE,
    status: 'ONLINE',
    version: 'control-runtime-1.2.0',
    gate: 'CONTROLLED',
    mode: MODE,
    liveFinancialExecution: false,
    financialTransactions: false,
    repositoryMutation: false,
    queue: QUEUE_NAME,
    repository: REPO,
    cloudTimeAuthority: {
      enabled: true,
      endpoint: '/time',
      source: 'Cloudflare Worker runtime',
      storageTimezone: 'UTC',
      displayTimezone: 'Asia/Bangkok',
    },
    endpoints: [
      'GET /',
      'GET /health',
      'GET /time',
      'POST /enqueue',
    ],
  });
}

function rootResponse(): Response {
  return json({
    service: SERVICE,
    status: 'ONLINE',
    version: 'control-runtime-1.2.0',
    gate: 'CONTROLLED',
    mode: MODE,
    liveFinancialExecution: false,
    queue: QUEUE_NAME,
    cloudTimeAuthority: true,
    endpoints: [
      'GET /',
      'GET /health',
      'GET /time',
      'POST /enqueue',
    ],
  });
}

function hasValidBusinessEvidence(result: AxExecutionResult, expectedTaskId: string): boolean {
  const evidence = result.evidence;
  return !!evidence &&
    typeof evidence === 'object' &&
    String(evidence.taskId || '') === expectedTaskId;
}

function hasVerifiedWriteBack(result: AxExecutionResult): boolean {
  return result.writeBackVerified === true;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/') return rootResponse();
    if (request.method === 'GET' && url.pathname === '/health') return healthResponse();
    if (request.method === 'GET' && url.pathname === '/time') return cloudTimeResponse(request);

    if (request.method === 'POST' && url.pathname === '/enqueue') {
      const auth = request.headers.get('Authorization') || '';
      if (!auth.startsWith('Bearer ')) return json({ error: 'AUTH_REQUIRED' }, 401);
      const token = auth.slice(7).trim();
      if (!token || token.length > 512) return json({ error: 'AUTH_INVALID' }, 401);

      const repoHeader = request.headers.get('X-AERIS-REPOSITORY') || '';
      if (repoHeader !== REPO) return json({ error: 'REPOSITORY_NOT_ALLOWED', expected: REPO }, 403);
      if (!(await verifyGitHubToken(token))) return json({ error: 'GITHUB_TOKEN_REJECTED' }, 403);

      const contentLength = Number(request.headers.get('content-length') || '0');
      if (Number.isFinite(contentLength) && contentLength > MAX_PAYLOAD_BYTES) {
        return json({ error: 'PAYLOAD_TOO_LARGE', maxBytes: MAX_PAYLOAD_BYTES }, 413);
      }

      let event: AxEvent;
      try {
        const rawBody = await request.text();
        if (new TextEncoder().encode(rawBody).byteLength > MAX_PAYLOAD_BYTES) {
          return json({ error: 'PAYLOAD_TOO_LARGE', maxBytes: MAX_PAYLOAD_BYTES }, 413);
        }
        event = JSON.parse(rawBody) as AxEvent;
      } catch {
        return json({ error: 'INVALID_JSON' }, 400);
      }

      if (!event || typeof event !== 'object' || !event.id || !event.taskId || !event.domain || !event.action) {
        return json({ error: 'EVENT_SCHEMA_INVALID', required: ['id', 'taskId', 'domain', 'action'] }, 422);
      }

      const normalizedEvent: AxEvent = {
        id: String(event.id),
        taskId: String(event.taskId),
        domain: String(event.domain),
        priority: Number(event.priority || 0),
        action: String(event.action),
        createdAt: event.createdAt || new Date().toISOString(),
        source: event.source || 'AX_CONTROL_RUNTIME',
      };

      await env.AX_EXECUTION_QUEUE.send(normalizedEvent);
      return json({
        accepted: true,
        queued: true,
        eventId: normalizedEvent.id,
        taskId: normalizedEvent.taskId,
        queue: QUEUE_NAME,
        executionGate: 'CONTROLLED',
        liveFinancialExecution: false,
      });
    }

    return json({ error: 'NOT_FOUND', service: SERVICE, status: 'ONLINE' }, 404);
  },

  async queue(batch: MessageBatch<AxEvent>): Promise<void> {
    for (const message of batch.messages) {
      const event = message.body;
      console.log(JSON.stringify({
        event: 'AX_EXECUTION_EVENT_RECEIVED',
        queue: batch.queue,
        messageId: message.id,
        body: event,
        receivedAt: new Date().toISOString(),
      }));

      if (event.domain !== 'AERIS') {
        console.log(JSON.stringify({ event: 'AX_EXECUTION_EVENT_DEFERRED', reason: 'DOMAIN_EXECUTOR_NOT_IMPLEMENTED', taskId: event.taskId, domain: event.domain }));
        message.ack();
        continue;
      }

      const payload = JSON.stringify({ jobId: event.id, command: event.action });
      const response = await fetch('https://aeris-execution-runtime.aerismusic8.workers.dev/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'User-Agent': 'AX-Control-Runtime/1.2.0' },
        body: payload,
      });

      const rawResponse = await response.text();
      let result: AxExecutionResult | null = null;
      try { result = rawResponse ? JSON.parse(rawResponse) as AxExecutionResult : null; } catch { result = null; }

      console.log(JSON.stringify({ event: 'AERIS_EXECUTION_RESULT', taskId: event.taskId, jobId: event.id, httpStatus: response.status, response: result ?? rawResponse }));

      const responseTaskMatches = result?.taskId === event.taskId;
      const businessEvidenceValid = result ? hasValidBusinessEvidence(result, event.taskId) : false;
      const writeBackVerified = result ? hasVerifiedWriteBack(result) : false;

      if (!response.ok ||
          result?.accepted !== true ||
          result?.verified !== true ||
          result?.executed !== true ||
          !responseTaskMatches ||
          !businessEvidenceValid ||
          !writeBackVerified) {
        throw new Error(`AERIS_EXECUTION_NOT_VERIFIED:${response.status}`);
      }

      console.log(JSON.stringify({
        event: 'AX_EXECUTION_VERIFIED',
        taskId: event.taskId,
        jobId: event.id,
        status: result.status || 'VERIFIED',
        evidenceTaskId: result.evidence?.taskId,
        writeBackVerified: result.writeBackVerified,
      }));
      message.ack();
    }
  },
} satisfies ExportedHandler<Env, AxEvent>;
