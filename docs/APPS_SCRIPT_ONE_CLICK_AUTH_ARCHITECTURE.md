# AERIS Apps Script One-Click Authorization Architecture

## Objective
After one-time Google authorization, K should only need to approve a deployment/action. No OAuth refresh token, client secret, or CLASPRC JSON is pasted into chat.

## Design

1. GitHub remains the canonical source.
2. AERIS Apps Script exposes a controlled bootstrap/deployment function.
3. The Apps Script project requests the minimum required OAuth scope for project content management:
   `https://www.googleapis.com/auth/script.projects`
4. K authorizes Google once from the Apps Script authorization UI.
5. The script uses `ScriptApp.getOAuthToken()` server-side to call the Apps Script REST API.
6. The bridge can then read/update Apps Script project content and create deployments.
7. All deployment actions must emit evidence and verification records before being reported as successful.

## Security

- Never transmit ScriptApp OAuth tokens to a browser/client.
- Never store OAuth tokens in GitHub source.
- Financial/live-money execution remains disabled.
- Deployment is an explicit approved action; ordinary repository pushes do not silently overwrite production.
- `projects.updateContent` overwrites project files, so a production backup/readback must happen before a write.

## Important limitation
Google's authorization model necessarily requires an initial user consent/authorization event. It cannot be eliminated by code. The target therefore is **one user authorization approval**, followed by automated token refresh and deployment. Google documents offline access for long-running server-side applications and Apps Script `projects.updateContent` requires the `script.projects` OAuth scope.

## Target flow

`K → Approve Google access once → token retained by Google Apps Script authorization → GitHub source → Apps Script API → verification → A MASTER BRAIN evidence`

## Current repository status

The repository already contains the clasp deployment bridge. This document defines the safer one-click authorization direction that avoids requiring K to paste `CLASPRC_JSON` into GitHub.
