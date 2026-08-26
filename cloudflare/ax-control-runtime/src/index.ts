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

function healthResponse(): Response {
  return json({
    service: SERVICE,
    status: 'ONLINE',
    version: 'control-runtime-1.0.0',
    gate: 'CONTROLLED',
    mode: MODE,
    liveFinancialExecution: false,
    financialTransactions: false,
    repositoryMutation: false,
    queue: QUEUE_NAME,
    repository: REPO,
    endpoints: [
      'GET /',
      'GET /health',
      'POST /enqueue',
    ],
  });
}

function rootResponse(): Response {
  return json({
    service: SERVICE,
    status: 'ONLINE',
    version: 'control-runtime-1.0.0',
    gate: 'CONTROLLED',
    mode: MODE,
    liveFinancialExecution: false,
    queue: QUEUE_NAME,
    endpoints: [
      'GET /',
      'GET /health',
      'POST /enqueue',
    ],
  });
}

export default {
  async fetch(
    request: Request,
    env: Env,
  ): Promise<Response> {
    const url = new URL(request.url);

    // ============================================================
    // ROOT
    // ============================================================

    if (request.method === 'GET' && url.pathname === '/') {
      return rootResponse();
    }

    // ============================================================
    // HEALTH
    // ============================================================

    if (request.method === 'GET' && url.pathname === '/health') {
      return healthResponse();
    }

    // ============================================================
    // ENQUEUE
    // ============================================================

    if (request.method === 'POST' && url.pathname === '/enqueue') {
      const auth = request.headers.get('Authorization') || '';

      if (!auth.startsWith('Bearer ')) {
        return json(
          {
            error: 'AUTH_REQUIRED',
          },
          401,
        );
      }

      const token = auth.slice(7).trim();

      if (!token || token.length > 512) {
        return json(
          {
            error: 'AUTH_INVALID',
          },
          401,
        );
      }

      const repoHeader =
        request.headers.get('X-AERIS-REPOSITORY') || '';

      if (repoHeader !== REPO) {
        return json(
          {
            error: 'REPOSITORY_NOT_ALLOWED',
            expected: REPO,
          },
          403,
        );
      }

      const tokenValid = await verifyGitHubToken(token);

      if (!tokenValid) {
        return json(
          {
            error: 'GITHUB_TOKEN_REJECTED',
          },
          403,
        );
      }

      const contentLength =
        Number(
          request.headers.get('content-length') || '0',
        );

      if (
        Number.isFinite(contentLength) &&
        contentLength > MAX_PAYLOAD_BYTES
      ) {
        return json(
          {
            error: 'PAYLOAD_TOO_LARGE',
            maxBytes: MAX_PAYLOAD_BYTES,
          },
          413,
        );
      }

      let event: AxEvent;

      try {
        const rawBody = await request.text();

        if (
          new TextEncoder().encode(rawBody).byteLength >
          MAX_PAYLOAD_BYTES
        ) {
          return json(
            {
              error: 'PAYLOAD_TOO_LARGE',
              maxBytes: MAX_PAYLOAD_BYTES,
            },
            413,
          );
        }

        event = JSON.parse(rawBody) as AxEvent;
      } catch {
        return json(
          {
            error: 'INVALID_JSON',
          },
          400,
        );
      }

      if (
        !event ||
        typeof event !== 'object' ||
        !event.id ||
        !event.taskId ||
        !event.domain ||
        !event.action
      ) {
        return json(
          {
            error: 'EVENT_SCHEMA_INVALID',
            required: [
              'id',
              'taskId',
              'domain',
              'action',
            ],
          },
          422,
        );
      }

      const normalizedEvent: AxEvent = {
        id: String(event.id),
        taskId: String(event.taskId),
        domain: String(event.domain),
        priority: Number(event.priority || 0),
        action: String(event.action),
        createdAt:
          event.createdAt ||
          new Date().toISOString(),
        source:
          event.source ||
          'AX_CONTROL_RUNTIME',
      };

      await env.AX_EXECUTION_QUEUE.send(
        normalizedEvent,
      );

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

    // ============================================================
    // METHOD / ROUTE NOT FOUND
    // ============================================================

    return json(
      {
        error: 'NOT_FOUND',
        service: SERVICE,
        status: 'ONLINE',
        endpoints: [
          'GET /',
          'GET /health',
          'POST /enqueue',
        ],
      },
      404,
    );
  },

  async queue(
    batch: MessageBatch<AxEvent>,
  ): Promise<void> {
    for (const message of batch.messages) {
      console.log(
        JSON.stringify({
          event: 'AX_EXECUTION_EVENT_RECEIVED',
          queue: batch.queue,
          messageId: message.id,
          body: message.body,
          receivedAt: new Date().toISOString(),
        }),
      );

      message.ack();
    }
  },
} satisfies ExportedHandler<Env, AxEvent>;
