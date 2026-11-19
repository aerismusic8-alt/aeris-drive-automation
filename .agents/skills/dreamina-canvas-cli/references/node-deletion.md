# Delete nodes

Read this file before deleting nodes. Check the current CLI's `schema "node delete"`
and its `confirm` and `status` subcommands for parameters. Shared approval and error
handling rules are in the [main Skill](../SKILL.md).

## Supported scope

- Supported types: `image`, `video`, `audio`, `element`, `text`, `timeline`, `file`.
- Each batch accepts at most 100 distinct Node IDs; duplicates are removed. Use
  comma-separated IDs or repeat `--node-id`.
- Groups cannot be deleted. Ordinary nodes inside a group can be deleted while
  preserving their parent and unselected siblings. Any group, missing or invalid
  target rejects the entire batch.
- Deletion cleans up related connections and references. It does not delete media
  resources, cancel accepted generation tasks or refund credits.

## Show the summary and wait for approval

Query the targets first, for example two nodes on the current canvas:

```bash
dreamina-canvas node delete --node-id node_0000000001,node_0000000002 --format json
```

This call only queries a summary. It exits with `10`, leaves stdout empty, and
returns approval details in stderr's `deletionConfirmation`. Pass `--project-id`
explicitly for another canvas.

Show the canvas, node names, and each node's current child, edge and reference
counts, then wait for explicit approval. Do not expand the set of related nodes.
Use `totals` for totals; do not add edge and reference counts together. Counts may
change as the canvas changes. Execution still deletes only the approved Node ID
list and cleans up its relationships at execution time.

Save the summary's `projectId`, `nodeIds` and `updateId` as `PROJECT_ID`,
comma-separated `NODE_IDS` and `UPDATE_ID` in the examples below. These values
identify the same deletion batch during confirmation, execution and status queries.

**Without explicit approval, do not call `confirm` or answer the terminal prompt
on the user's behalf.** In a table-mode interactive terminal, the user can enter
`y` to confirm and execute; `N` or EOF deletes nothing. `--yes` alone cannot replace
approval and the deletion token.

## Confirm and execute after approval

Use the approved original project, Node IDs and batch:

```bash
dreamina-canvas node delete confirm --project-id "$PROJECT_ID" --node-id "$NODE_IDS" --update-id "$UPDATE_ID" --format json
```

This command does not delete nodes. Use its `data.deleteConfirmationToken` as
`DELETE_TOKEN` and execute before `data.expiresAtMs`:

```bash
dreamina-canvas node delete --project-id "$PROJECT_ID" --node-id "$NODE_IDS" --update-id "$UPDATE_ID" --delete-token "$DELETE_TOKEN" --format json
```

Use the token only to connect these two steps; do not show it to the user or store
it in logs or long-lived records. Report the batch outcome after success.
`idempotentReplay=true` means an existing result was returned, not another deletion.

## Handle uncertain results or invalid targets

After a timeout, lost response, or otherwise unconfirmed execution result, query the original batch
first. You can also recover its project, Node IDs and `updateId` from the error's
`deletionRecovery`. The query needs no deletion token:

```bash
dreamina-canvas node delete status --project-id "$PROJECT_ID" --node-id "$NODE_IDS" --update-id "$UPDATE_ID" --format json
```

| Query result | Next action |
| --- | --- |
| `found=true`, `result=accepted` | Report the original batch as successful; do not delete again or count it twice. |
| `found=true`, `result=rejected` | Report that the entire batch was rejected; do not retry automatically. Inspect optional `data.error`; do not guess a cause when details are absent. |
| `found=false` | No result was found. Do not report success or automatically create a new batch. If a retry is needed, reuse the original project, list, `updateId` and valid token. If the token expired, call `confirm` again for the same approved batch. |

For other errors, follow structured fields and the [shared error handling rules](../SKILL.md).
Read `diagnostics[].detail` for the known offending node and original input position
and inspect its Node ID with `node show`. **Changing the target list requires a new summary,
explicit approval and a new `updateId`.** Split more than 100 distinct IDs into
batches; show the summary and obtain approval for each batch.

Keep the original account and canvas for this batch; follow [identity and local-record recovery](recovery-and-idempotency.md) if the context or record is unavailable. For deletion, inspect with `node delete status` using the original `projectId/nodeIds/updateId`, not the generation wait command. A successful result with `localStorageWarning` remains successful: inspect the original batch rather than delete again.

Calling `node delete confirm` for an already completed batch returns `error.code=5` with the completed-batch cause without a new token; a rejected batch retains its original rejection details. Inspect the result with `node delete status` rather than confirm a completed batch again.
