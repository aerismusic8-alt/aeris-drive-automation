import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { request } from 'node:http';
import { nodeForTask, loadNodeRegistry, heartbeatNode } from './node-control.mjs';

export async function dispatchToPc1(job, adapter) {
  if (!adapter || typeof adapter.execute !== 'function') throw new Error('PC1 adapter is required');
  return adapter.execute(job);
}

export function createLocalPc1Adapter({
  command = process.execPath,
  executorPath = resolve(dirname(fileURLToPath(import.meta.url)), 'pc1-specialist.mjs')
} = {}) {
  if (!command) throw new Error('PC1 executor command is not configured');
  return { async execute(job) {
    const { spawn } = await import('node:child_process');
    return new Promise((resolvePromise, reject) => {
      const child = spawn(command, [executorPath, JSON.stringify(job)], {
        shell: false,
        stdio: ['ignore', 'pipe', 'pipe']
      });
      let out = '', err = '';
      child.stdout.on('data', d => { out += d; });
      child.stderr.on('data', d => { err += d; });
      child.on('error', reject);
      child.on('close', code => {
        if (code !== 0) return reject(new Error(`PC1 executor exited ${code}: ${err.trim()}`));
        try {
          resolvePromise(JSON.parse(out));
        } catch {
          reject(new Error(`PC1 executor returned invalid JSON: ${out}`));
        }
      });
    });
  }};
}

function postJson(url, payload, timeoutMs = 30000) {
  return new Promise((resolvePromise, reject) => {
    const target = new URL(url);
    const body = JSON.stringify(payload);
    const req = request(
      {
        hostname: target.hostname,
        port: target.port || 80,
        path: target.pathname + target.search,
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body)
        }
      },
      res => {
        let out = '';
        res.setEncoding('utf8');
        res.on('data', d => { out += d; });
        res.on('end', () => {
          try {
            const parsed = JSON.parse(out);
            if (res.statusCode >= 200 && res.statusCode < 300) {
              resolvePromise(parsed);
            } else {
              reject(new Error(`NODE_HTTP_${res.statusCode}: ${out}`));
            }
          } catch {
            reject(new Error(`NODE_INVALID_JSON: ${out}`));
          }
        });
      }
    );
    req.setTimeout(timeoutMs, () => req.destroy(new Error('NODE_HTTP_TIMEOUT')));
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

export function createAxNodeDispatcher({
  localAdapter = createLocalPc1Adapter(),
  nodeUrls = {}
} = {}) {
  return async function dispatch(job) {
    const registry = await loadNodeRegistry();
    const node = nodeForTask(job, registry);
    if (!node) throw new Error('NO_EXECUTION_NODE_AVAILABLE');

    if (node.nodeId === 'PC1-MAIN' && node.transport === 'local') {
      await heartbeatNode('PC1-MAIN', { activeJob: job.task_id });
      try {
        const result = await localAdapter.execute(job);
        await heartbeatNode('PC1-MAIN', {
          activeJob: null,
          lastVerifiedJob: job.task_id
        });
        return result;
      } catch (error) {
        await heartbeatNode('PC1-MAIN', {
          activeJob: null,
          status: 'DEGRADED',
          lastError: error.message
        });
        throw error;
      }
    }

    const base =
      nodeUrls[node.nodeId] ||
      process.env[`AX_${node.nodeId.replaceAll('-', '_')}_URL`];

    if (!base) {
      throw new Error(`NODE_TRANSPORT_NOT_CONFIGURED: ${node.nodeId}`);
    }

    await heartbeatNode(node.nodeId, { activeJob: job.task_id });

    try {
      const result = await postJson(
        new URL('/dispatch', base).toString(),
        { protocol: 'AX-NODE/1', nodeId: node.nodeId, job }
      );
      await heartbeatNode(node.nodeId, {
        activeJob: null,
        lastVerifiedJob: job.task_id
      });
      return result;
    } catch (error) {
      await heartbeatNode(node.nodeId, {
        activeJob: null,
        status: 'DEGRADED',
        lastError: error.message
      });
      throw error;
    }
  };
}
