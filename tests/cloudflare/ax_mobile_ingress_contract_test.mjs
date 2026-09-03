import assert from 'node:assert/strict';

const worker = (await import('../../cloudflare/ax-control-runtime/src/index.ts')).default;

const inbox = {
  idFromName: () => 'gateway',
  get: () => ({
    fetch: async (input) => {
      const request = input instanceof Request ? input : new Request(String(input));
      const url = new URL(request.url);
      const body = await request.json().catch(() => ({}));
      if (url.pathname === '/put') {
        return new Response(JSON.stringify({ ok: true, requestId: body.record.request_id }), { status: 201 });
      }
      if (url.pathname === '/pull') {
        return new Response(JSON.stringify({ ok: true, item: null }), { status: 200 });
      }
      return new Response(JSON.stringify({ ok: false }), { status: 400 });
    },
  }),
};

async function request(path, { method = 'GET', headers = {}, body } = {}) {
  return worker.fetch(
    new Request(`https://ax-control-runtime.test${path}`, {
      method,
      headers: { 'content-type': 'application/json', ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    {
      AX_MOBILE_INGRESS_SECRET: 'test-mobile-secret',
      AX_PC_PULL_SECRET: 'test-pc-secret',
      AX_GATEWAY_INBOX: inbox,
    },
  );
}

const unauthorized = await request('/mobile/input', {
  method: 'POST',
  body: { taskId: 'TASK-1', contentType: 'text', content: 'hello', sourceChannel: 'MOBILE' },
});
assert.equal(unauthorized.status, 401);

const valid = await request('/mobile/input', {
  method: 'POST',
  headers: { Authorization: 'Bearer test-mobile-secret' },
  body: { taskId: 'TASK-1', contentType: 'text', content: 'hello', sourceChannel: 'MOBILE' },
});
assert.equal(valid.status, 201);
const validBody = await valid.json();
assert.equal(validBody.accepted, true);
assert.equal(validBody.transportStore, 'AX_GATEWAY_INBOX');
assert.equal(validBody.sourceChannel, 'MOBILE');
assert.equal(validBody.taskId, 'TASK-1');

const invalidSource = await request('/mobile/input', {
  method: 'POST',
  headers: { Authorization: 'Bearer test-mobile-secret' },
  body: { taskId: 'TASK-1', contentType: 'text', content: 'hello', sourceChannel: 'GPT' },
});
assert.equal(invalidSource.status, 422);

const config = await request('/mobile/config');
assert.equal(config.status, 200);
const configBody = await config.json();
assert.equal(configBody.mobileIngress, true);
assert.equal(configBody.pcPull, true);
assert.equal(configBody.executionMode, 'FREE_ONLY');
assert.equal(configBody.liveFinancialExecution, false);

const pcUnauthorized = await request('/pc/pull');
assert.equal(pcUnauthorized.status, 401);

const pcPull = await request('/pc/pull', {
  method: 'POST',
  headers: { Authorization: 'Bearer test-pc-secret' },
});
assert.equal(pcPull.status, 200);
const pcPullBody = await pcPull.json();
assert.equal(pcPullBody.item, null);

console.log('AX mobile ingress contract: PASS');
