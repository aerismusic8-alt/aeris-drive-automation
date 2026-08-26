type AxEvent = {
  id: string;
  taskId: string;
  domain: string;
  priority: number;
  action: string;
  createdAt: string;
  source: string;
};

type Env = {
  AX_EXECUTION_QUEUE: Queue<AxEvent>;
};

const REPO = 'aerismusic8-alt/aeris-drive-automation';
const MAX_PAYLOAD_BYTES = 16_000;

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { 'Cache-Control': 'no-store' },
  });
}

async function verifyGitHubToken(token: string): Promise<boolean> {
  const response = await fetch(`https://api.github.com/repos/${REPO}`, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2026-03-10',
      'User-Agent': 'AX-AERIS-Control-Runtime',
    },
  });
  return response.ok;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'GET' && url.pathname === '/health') {
      return json({
        service: 'AX CONTROL RUNTIME',
        status: 'ONLINE',
        mode: 'FREE_ONLY',
        liveFinancialExecution: false,
        queue: 'ax-execution-events',
      });
    }

    if (request.method !== 'POST' || url.pathname !== '/enqueue') {
      return json({ error: 'NOT_FOUND' }, 404);
    }

    const auth = request.headers.get('Authorization') || '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'AUTH_REQUIRED' }, 401);
    const token = auth.slice(7).trim();
    if (!token || token.length > 512) return json({ error: 'AUTH_INVALID' }, 401);

    const repoHeader = request.headers.get('X-AERIS-REPOSITORY');
    if (repoHeader !== REPO) return json({ error: 'REPOSITORY_NOT_ALLOWED' }, 403);

    if (!(await verifyGitHubToken(token))) return json({ error: 'GITHUB_TOKEN_REJECTED' }, 403);

    const length = Number(request.headers.get('content-length') || '0');
    if (length > MAX_PAYLOAD_BYTES) return json({ error: 'PAYLOAD_TOO_LARGE' }, 413);

    let event: AxEvent;
    try {
      event = await request.json() as AxEvent;
    } catch {
      return json({ error: 'INVALID_JSON' }, 400);
    }

    if (!event.id || !event.taskId || !event.domain || !event.action) {
      return json({ error: 'EVENT_SCHEMA_INVALID' }, 422);
    }

    await env.AX_EXECUTION_QUEUE.send(event);
    return json({ accepted: true, queued: true, eventId: event.id });
  },

  async queue(batch: MessageBatch<AxEvent>): Promise<void> {
    for (const message of batch.messages) {
      console.log(JSON.stringify({
        event: 'AX_EXECUTION_EVENT_RECEIVED',
        queue: batch.queue,
        messageId: message.id,
        body: message.body,
      }));
    }
  },
} satisfies ExportedHandler<Env, AxEvent>;
