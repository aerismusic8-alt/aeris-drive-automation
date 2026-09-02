# Apps Script Deployment Bridge

## Status
IMPLEMENTED — CREDENTIAL/PROJECT VERIFICATION PENDING

## Purpose
Allow the repository to deploy the AERIS Apps Script project through `clasp`, so source fixes do not require manual copy/paste.

## Required GitHub Actions secrets
- `AERIS_APPS_SCRIPT_ID`: Apps Script project ID.
- `CLASPRC_JSON`: OAuth credentials generated for clasp with permission to edit the target Apps Script project.

Never commit either secret.

## Flow
GitHub main push / manual workflow
→ checkout
→ generate `.clasp.json` from secret
→ authenticate clasp
→ `clasp push --force`
→ `clasp status`

## Safety
This bridge does not claim production success merely because `clasp push` succeeds. After deployment, Apps Script Executions must prove the target function ran successfully. For the current AERIS scope bug, verification requires a subsequent `AERIS_DELEGATION_QUEUE_TRIGGER` execution with no `ReferenceError: data is not defined`.

## Important
`clasp push` updates the Apps Script project source. It does not by itself prove that a deployed web-app version or business workflow is correct. Deployment/version behavior must be verified separately when required.
