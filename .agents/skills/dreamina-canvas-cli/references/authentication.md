# Authentication and execution permissions

## Local business-state storage

`error.localStorage` identifies a current-canvas or operation-record failure, independently of credential storage. Inspect `reason`, `stage`, and the local `directory`; do not infer a service outage or enable full access. Request the host's supported approval for operations within that directory, including temporary files, replacement, and cleanup. If necessary, explicitly set `DREAMINA_CANVAS_STATE_DIR` to an approved private persistent absolute directory for all related CLI invocations. This option changes business records only, not authentication credentials, and requires a CLI version that supports it.

An explicit `--project-id` chooses the target canvas without changing the selection. The server still verifies the account, canvas permissions, and applicable usage eligibility; generation still requires a recovery record. Preserve the original project and submission IDs. Do not clear records or switch directories automatically on permission, corruption, or disk-space errors. Local-only failure does not prove a remote generation failed. Share diagnostics without credential values, record contents, or private prompts.

Use `error.localStorage` to distinguish the store, I/O stage, reason, and `submissionPhase`. `before_submit` means only this invocation stopped before sending; preserve the original project and submission IDs. `after_submit` requires read-only `operation status/wait <submitId> --project-id <projectId>`; do not recreate or resubmit. If only the operation journal is unavailable, a read-only remote lookup can continue while the account and selected space remain usable; `localStorageWarning` does not negate a successful remote result. If `canvas create --use` returns `current=false` and a warning, the canvas already exists: keep its `webUrl`, deliver it under the main Skill's canvas link rules, and pass its `--project-id` explicitly. Keep damaged records for diagnosis; do not overwrite or delete them to make a retry pass.

## Authentication

Before model discovery, use `auth status` with the intended profile. Continue with
an existing usable login; otherwise use `auth login` from the installed schema.
Read the numeric `error.code`, original `error.reason`, and any verified diagnostics together with the authentication state. JSON error messages are always English, while human output follows the artifact's distribution.

### Open the authorization page

`auth login` automatically attempts to open this login's `verificationUriComplete` in the system default browser; also send the user a clickable link, and do not reopen an authorization page that is already open. When the session briefing specifies another way to open it, such as the host's built-in browser or not sending the link in the reply, use `auth login --no-browser` to get the link and follow the briefing. After opening it, run `auth wait` immediately; the user signs in and confirms on the page. If opening fails, state the actual reason, do not claim it opened, and send the link.

### Device Flow: run `auth wait` after receiving the link

Interactive `auth login` waits for authorization; the non-interactive calls commonly used by Agents return a challenge first. **Exit code 0, opening the authorization page, or the user saying "authorized" does not by itself prove that the CLI is signed in.** Branch on the returned `data.status`:

1. `reused` or `logged_in`: the login is usable. Continue the original task without starting another authorization.
2. `authorization_required`: if not already said in this turn, say briefly that generation can start as soon as authorization is complete (name the actual action for other tasks), without repeating it. Retain `data.challenge` and open `verificationUriComplete` as described above. If no complete URL is available, open `verificationUri` and provide the `userCode` to enter on the page. Do not present `deviceCode` as the user code. Reuse this authorization request instead of rerunning `auth login` because the page was opened again.
3. After opening the authorization page, wait for the user's authorization without stopping for a reply. Immediately run the wait command below under the same OS user, binary, profile, and runtime configuration, waiting up to 5 minutes. Set `--device-code` to the actual `data.challenge.deviceCode` from this login, not `userCode` or the authorization URL. The CLI polls, exchanges authorization for credentials, and saves them; **a loop of `auth status` calls or merely waiting for a user reply cannot replace this step.**

```bash
dreamina-canvas auth wait --device-code '<data.challenge.deviceCode>' --profile '<same profile as auth login>' --timeout 5m
```

Replace the placeholders. If login used the default profile, keep that default for wait. Commands and fields must match the installed schema.

4. When wait returns `data.status=logged_in`, use that success result to continue the user's original task automatically, without asking the user to confirm that authorization is done; later generation still follows the existing credit approval rules. If the host tool reports that the process is still running, collect that process's result instead of starting another wait concurrently or rerunning login.

| Wait result | Next action |
| --- | --- |
| `error.code=40011` during authorization wait | Only this single wait budget elapsed. Retain the original device code and keep waiting while the challenge remains valid and this turn's automatic wait budget is not used up; do not generate another authorization link. If the user postpones authorization, pause. |
| `error.code=40014` | The challenge expired. When login is still needed, run ordinary `auth login` again and use the new challenge. |
| Other errors | Use the verified cause and authentication facts below. Stop on denied authorization or unrecoverable errors instead of retrying indefinitely. |

**Authorization wait limit:** Start the clock at this turn's first `auth wait`; wait automatically for at most 5 minutes in total. Each wait uses a timeout no longer than the remaining budget, and neither a single timeout nor a new challenge resets the total. When a wait process is already running, read its result instead of starting another. When the limit is reached, stop waiting automatically and say that authorization is not complete; resume according to whether the challenge is still valid only after the user decides to continue. When the user denies authorization or authorization fails unrecoverably, stop waiting at once, briefly introduce Dreamina's creative capabilities and any applicable offers supported by the session briefing without claiming they were granted, and do not start authorization again automatically.

Do not start another login, log out, or use `--force` merely because authorization is pending. `--force` clears the current profile's login state; it is not an authorization-wait step.

| `error.reason` | Recovery |
| --- | --- |
| `dns_resolution_failed` | Check DNS and network permissions for the actual CLI process. A successful homepage curl does not prove CLI access. |
| `network_permission_denied` | Request necessary network permission through the host's supported approval flow. |
| `credential_store_permission_denied` | Request necessary local credential storage permission. Network approval alone may be insufficient. |
| `credential_store_unavailable` / `credential_store_corrupt` | Check OS storage and user context; preserve records and contact support before clearing or replacing them. |
| `network_timeout` | Retry with backoff at most twice, then retain the sanitized error for support. |
| `auth_dependency_failed` | Cause is unclassified. Compare once with an approved execution or regular terminal; do not conclude the service is down. |

For DNS or permission failures, retry once only after conditions change. Reuse
permissions already granted; do not automatically enable full access. If the host
cannot grant the necessary access, have the user run the same binary with the same
profile in a regular terminal under the same OS user. After terminal authorization,
check `auth status` again in the Agent environment; subsequent requests may still
need permissions. If the error omits `reason`, permit the same single comparison without guessing a cause.

After sign-in or authorization waiting completes, use that success result directly. Follow the main Skill for the capabilities exposed by the installed schema. For an existing login without an authorization result in this interaction, use `auth account` to obtain current account information. `auth status` checks credential state; it does not replace server identity verification. Use the returned errors and supported auth commands instead of assuming that credentials can be refreshed. On `reason=account_changed`, stop automatic retries, verify the intended account with `auth account`, and preserve the original operation identity.

Credential storage depends on the installed CLI and operating system. Use the
actual error to identify the required permission; do not infer an internal path
or storage backend from this guide. Do not use sudo or administrator mode by
default, export tokens, clear credential storage, or move credentials into a
workspace or shared temporary directory.


Use `auth account` when the user asks about the current personal membership tier, credits, or their respective expiry. Follow the installed CLI's `schema` and current response. Missing information stays unknown; do not infer membership expiry from credit expiry or vice versa, or use display facts in place of generation quotes, credit approval, or server admission.


## Installation and upgrade permissions

The installer needs write access inside the binary installation directory and the target Skill directory. Creating a new target also requires permission to create it in its parent. Upgrades preserve the `dreamina-canvas-cli` root directory and update its contents without moving or deleting that root.

If access is denied, request the necessary one-time approval for the actual installation command through the host. If the host cannot grant access, install from a regular terminal under the same OS user. Installation failures do not require logging out or clearing credentials. If an installation lock exists, first check for an active installer. If a retained backup path is reported, recover or inspect that backup before further cleanup. Do not load the Skill during installation; use a fresh conversation after it completes.

When installing a supplied complete bundle, run its `install.sh` from the extracted directory or set `DREAMINA_CANVAS_PAYLOAD_DIR` to that directory’s absolute path. Keep `payload.sha256`, the matching platform binary, `skill.tar.gz`, and `version.json` together. An incomplete or mismatched bundle must not fall back to CDN. Verify the installed CLI using the absolute path and version printed by the installer, and load the updated Skill in a fresh conversation. A PATH warning does not mean installation failed.

When the error includes a `clientUpgrade` requirement, select a `clientUpgrade.installCommands` entry matching the OS and terminal, if provided. Windows PowerShell and CMD use different commands. Without these entries, follow the `upgradeUrl` guidance and do not infer other script paths. An upgrade response does not itself authorize command execution. After updating, verify the CLI version and read the updated Skill; retain the current profile and credentials. Continue the original `operationRef` when present instead of submitting again.
