# AX External K Command Channels

## Current implemented external surfaces

### 1. AX Mobile Gateway
Base runtime: `https://ax-control-runtime.aerismusic8.workers.dev`
Surface: `/mobile`
Ingress: `/mobile/input`
Result: `/web/result/{request_id}` or the corresponding authenticated result path.

This is the first external K-facing channel to validate because it already exists in the deployed runtime and does not require ChatGPT as the conversation transport.

### 2. AX Web Chat
Surface: `/chat`
Ingress: `/web/input`
This is browser-based and can be used independently of the ChatGPT conversation, subject to the runtime's authentication/session contract.

## Security contract
- Protected input endpoints require authentication.
- Runtime remains `FREE_ONLY`.
- Live financial execution remains disabled.
- PC boundary uses the configured transport secret.
- Every request should carry a request ID and task ID for correlation.

## E2E target
A true external-channel test must demonstrate:

`K outside ChatGPT → external ingress → AX Runtime → execution dispatch → PC2 → result → AX Runtime → K-visible result`

A readiness contract that only stores a synthetic result is not sufficient to declare the execution path complete.

## Candidate next channels
- Telegram Bot
- LINE Official Account webhook
- Discord bot
- Direct mobile/PWA client

These are candidates only until credentials, webhook ownership and an actual end-to-end execution are configured and verified.
