# Credits and human approval

The credit protocol is a server-enforced spending-ceiling authorization, not a
client warning and not a promise that draft parameters stay unchanged.

## Mental model

```text
save latest draft
  -> authoritative quote
  -> user approves a ceiling when required
  -> server adjudicates against the latest draft before running
  -> run only if latest total <= approved ceiling
```

The user may edit a saved node after the quote. Run uses the latest authoritative
draft. If its latest price stays within the approved ceiling, the same approval
may remain valid; if it exceeds the ceiling, stop and request approval again.

## Required Agent behavior

1. Save the intended node plan before quoting: `node quote` prices saved nodes,
   so an unsaved plan cannot be quoted.
2. Treat `node quote` as read-only information. It does not authorize spending
   and never issues a token.
3. If all items are below the server threshold, run may not require a token.
4. If approval is required, check whether the user has already approved the same
   plan and a sufficient ceiling. If not, present the itemized quote, total,
   currency/credit unit, and the proposed credit limit for this run, then wait. Do not approve automatically.
5. Invoke `node confirm --credit-ceiling <n>` only after explicit user approval.
   It exposes a token for ordinary node runs; convenience workflows handle approval internally after the user approves.
6. Pass the resulting opaque token only to the intended `node run --credit-token`.
   Never log it or write it to job state.
7. If the latest authoritative total exceeds the ceiling, return to the user;
   do not silently lower output count or quality.

## Media `--run` runs the same four steps for you

`node create|edit image|video|audio --run` performs save, quote, approve, run in one invocation and pauses
between quote and run. It does not remove the approval requirement — it moves
where you supply the approval:

| How you approve | Meaning |
| --- | --- |
| `--credit-ceiling <n>` | Proceed only when the quote is at most `n`. The quote ceiling check still applies when the server requires no confirmation |
| `--credit-token <t>` | Already approved via `node confirm`; reuse that token |
| interactive `y/N` | The prompt states the amount; answering `n` stops with nothing spent |
| `--yes` | Answers the local approval prompt without an amount cap. Use only when the user has explicitly authorized that scope; it cannot replace a user-approved spending limit |

With none of these on a non-TTY stream, the command stops after the quote and
exits `10`. **The node is already saved and nothing has been charged.** The
failure envelope carries both halves you need:

```json
{
  "schemaVersion": "2",
  "error": { "code": 40018, "message": "This operation does not have the required approval." },
  "creditConfirmation": { "reason": "unconfirmed", "minimumCreditCeiling": 120 },
  "partialData": { "items": [{ "nodeId": "node_xxx", "submitId": "uuid" }] }
}
```

Do not treat this exit as a failed generation. Present the amount to the user,
then resume by reusing **both** identities from `partialData`:

- resume the saved node with its original `nodeId` and `submitId`, using the
  approved ceiling or token; do not save a second copy;
- if the operation has already been submitted, follow [operation recovery](recovery-and-idempotency.md)
  and inspect its original ID instead of running again.

An absent `minimumCreditCeiling` means the server could not compute occupancy
(`occupancy_unknown`). It is **not** zero — approving zero is guaranteed to be
rejected again. Escalate to the user instead.

Image, video, and audio use this same four-step path. Omit `--run` to save only,
or use `node quote` → `node confirm` → `node run` for a batch or explicit control.

## Image upscale uses its own approval scope

`node upscale image` operates on existing successful image nodes, not their ordinary generation drafts.
It creates a new node and resource per source. Do not use ordinary `node quote/confirm/run` to price or run it.
The command quotes before approval and uses an image-upscale-scoped approval;
an ordinary `node confirm` token is not interchangeable. Explicit ceilings remain binding below the threshold.
Without approval, exit `10` returns `partialData.items[].sourceNodeId/submitId`; no output node has been created.
After approval reuse those submit IDs and the original upscale arguments. Once submitted, use read-only
`operation status/wait` for recovery, not a new submit ID. Default behavior returns acceptance;
`--wait` observes the new resources (10 minutes maximum, 5-second interval by default).
`--dry-run` is local-only and cannot prove source eligibility, price or generation success.

To choose an available image upscaling model, use `--mode pro --model <image_upscale_model> --resolution 4K`.
Use the exact model key provided for the target environment. Do not add `--detail` when choosing a model;
normal mode does not accept a model. Missing model or price configuration fails rather than using base upscaling.

## Batch rules

- A confirmation batch must be fully quotable. A partial total is not a safe
  ceiling for the original batch.
- Keep per-item submit IDs and results even when only part of the batch is
  accepted.
- Retain the approved ceiling and returned per-item credit facts for recovery;
  do not infer available approval capacity when the response leaves it unknown.
- One failed item must not erase the identities or credit facts of accepted
  items.

## Confirmation versus idempotency

A confirmation token authorizes a spending ceiling; it is not the main duplicate
run defense. Submit IDs and the server's claimed submission records provide
idempotency.

On recovery, inspect the original submission before demanding a fresh token.
A known accepted submission is observed under its existing identity. An absent
record alone does not prove it is safe to submit again; follow the same recovery guide.

## What to show the user

Show:

- what will run and how many outputs are requested;
- the latest quote and the proposed credit limit for this run;
- any creative item that cannot be quoted yet;
- whether this starts a new generation or keeps waiting for an earlier one;
- why a new approval is required.

Do not describe the nominal pre-charge snapshot as final net spend or refund
status unless the release exposes settlement/ledger facts that prove it.

For example, `resource get` exposes `creditsAmount` as a resource credit snapshot. It can remain nonzero after a failed task has been refunded. Do not report it as the net charge or claim a refund solely from task failure; verify the credit ledger.
