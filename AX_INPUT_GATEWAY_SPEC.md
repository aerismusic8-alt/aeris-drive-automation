# AX Universal Input Gateway v1.0

## Objective

Decouple AX intake from a single AI/provider input limit. The gateway persists an input before downstream work and returns a verifiable `inputId` and SHA-256 content hash.

## Accepted inputs

- `TEXT` / `INLINE_TEXT`: direct text payload.
- `URL`: URL as text payload.
- `JSON`: structured JSON payload.
- `DRIVE_FILE`: an existing Google Drive `fileId`; metadata is resolved by Apps Script.

## Canonical lifecycle

`RECEIVED -> QUEUED -> PROCESSING -> COMPLETED` or `ERROR`

The current v1 module establishes the durable `RECEIVED` state. Downstream queue/dispatch wiring is deliberately additive so the existing `processCommandQueue()` trigger is not duplicated.

## API functions

### AX_INPUT_SUBMIT(request)

Returns `inputId`, `inputType`, `contentHash`, timestamp and verified persistence.

Example:

```json
{
  "source": "K",
  "inputType": "TEXT",
  "payload": "analyze this"
}
```

Drive file example:

```json
{
  "source": "K",
  "inputType": "DRIVE_FILE",
  "fileId": "<GOOGLE_DRIVE_FILE_ID>"
}
```

### AX_INPUT_STATUS(inputId)

Returns persisted metadata and current state.

### AX_INPUT_HEALTH()

Verifies that the input queue sheet exists and is readable.

## Safety

This gateway does not attempt to bypass provider security, authentication, quotas or access controls. It provides an independent, authorized ingress path and failover architecture.

No new `processCommandQueue()` trigger is created by this module.

## Activation

The module is committed to the existing AERIS Apps Script source tree. Full external endpoint activation still requires the deployed Apps Script project to pull this source and publish the route. That deployment step is kept separate from the baseline-safe source change so the existing production endpoint is not overwritten without runtime verification.
