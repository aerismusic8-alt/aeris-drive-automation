# OpenHands Free-First Runtime Policy

## Current Verified Facts

- OpenHands Agent Canvas is open source and can run a backend locally, in Docker, on a VM, or in cloud infrastructure.
- Agent Canvas supports local model servers and OpenAI-compatible providers, including Ollama and LM Studio.
- Agent Canvas can also use ACP agents such as Claude Code, Codex, and Gemini CLI, but those paths depend on the corresponding provider/subscription access.
- The current local setup requires Node.js 22.12+ and npm plus a model access path.
- The old OpenHands V1 CLI is no longer the recommended path; current documentation points to Agent Canvas.

## Cost Policy

`OPEN SOURCE RUNTIME != ZERO-COST MODEL INFERENCE`

OpenHands runtime may be free/self-hosted while model inference, search APIs, cloud sandboxes, or external services may still incur cost.

Therefore AX must evaluate runtime cost and model/tool cost separately.

## Provider Priority

1. Existing approved local model server.
2. Existing approved free model access.
3. Existing ACP subscription/free allowance when explicitly available.
4. Paid provider only after K approval.

## Limit Monitoring

Record observable provider/model usage where the integration exposes it. Do not assume a provider is unlimited because the runtime is open source.

## Fallback

If the preferred model/tool hits a free limit:

`DETECT LIMIT → SWITCH TO APPROVED FREE FALLBACK → VERIFY → CONTINUE`

If no approved free fallback exists:

`STOP → WAITING_K`

## Security

No API keys, cookies, tokens, credentials, or secret values belong in repository files, workflow output, Blueprint files, or audit logs.
