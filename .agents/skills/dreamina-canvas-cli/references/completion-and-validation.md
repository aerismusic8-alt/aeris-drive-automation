# Completion and validation

Choose checks for the user's requested deliverable. Task acceptance, terminal
execution, resource selection, and file download are different states; one does
not prove another. An image or video generation request does not require download
or timeline checks.

## Per-item states

For every output that requires generation, confirm:

1. the intended Node ID and submit ID are known;
2. the submission was accepted or safely recovered;
3. the operation reached a terminal state;
4. at least one usable Resource ID exists;
5. the selected resource matches the requested media type and creative intent.

Do not infer success from HTTP success, task acceptance, or an operation reference.

## Reference checks when needed

Consider these checks when the user requests preserved or verified references,
precise prompt binding is needed, or a reference issue occurs. They apply to
images, videos, Elements, and timelines, but are not a fixed prerequisite for
every generation. Skip them when there are no references.

1. Read `data.node` from the save response, or the corresponding FOUND item's
   `node` from `node show`. Verify `generation.references[]`,
   `subjectBindings.main/voice/auxiliaries[]`, or
   `timelineTracks.tracks[].clips[].source`, as applicable. The expected source
   must have `kind=node` and the original Node ID in `id`; a nested
   `resource.resourceId` is resolved output metadata, not a replacement source.
2. Require every intended upstream Node ID in `upstreamNodeIds`. Reference
   thumbnails, usable resources, or successful generation alone are insufficient.
   Check clip/reference order separately; the edge list is not the slot order.
3. When the creative plan needs an upstream object placed at an exact semantic
   position in the prompt, read back `generation.prompt` and
   `generation.promptParts[]`: the prompt should preserve the matching
   `{{node:<node-id>}}` placeholder, and `promptParts[]` should contain a reference
   part whose `referenceIndex` points to that same Node ID in
   `generation.references[]`. Seeing only `generation.references[]` or
   `upstreamNodeIds` does not prove that objects and their actions, positions, or
   relationships in the text are bound to the intended nodes.
4. When a resource reference is intentional, verify its ID and the recorded
   reason (no source node or explicit user-requested freezing). Do not require
   an inferred edge to a node that happens to contain that resource.
5. If provenance is wrong or prompt placement is missing, edit the existing node
   without `--run`, preserving unrelated fields and the complete generation
   configuration or timeline tracks required by the edit contract, then read back
   and check again. Do not regenerate or spend credits to repair a reference. If
   the saved source is already `kind=node` but the edge is missing, retain
   `meta.requestId`, Node IDs, and `savedDraftVersion` for diagnosis; do not
   downgrade to a resource reference.

Missing or truncated source, edge, or prompt-placement information leaves this
check unverified. Report that gap rather than declaring the canvas structure
complete.

## Canvas/sequence checks

These are Agent checks on the final result. Apply them only when the user
requested a multi-shot or multi-track sequence. A standalone image, video, or
audio asset does not require a timeline or unrelated media nodes. For sequence
work, confirm:

- all requested shots and audio segments exist without duplication;
- dependency order, timeline order, clip count, and duration match the
  user-approved plan;
- when audiovisual alignment is required, visuals cover the full requested audio
  span;
- downstream references meet the applicable checks above when the user requests
  reference validation.

## Timeline preconditions

The server validates the whole timeline plan and rejects it without saving
anything if any clip is invalid; the CLI checks only local formatting. Before
`node create|edit timeline`, satisfy every point below.

- Every `--clip` / `--audio-clip` references a node that already generated
  successfully and has a usable image, video, or audio output, or an existing
  asset-library resource. If a source is not ready, wait for an already-submitted
  generation to finish; if it has never been submitted, generate it first.
  Assemble only after the output is available.
- The total clip count across all tracks is at most 20 per request; split a
  larger assembly across timeline nodes or edits.
- Audio clips never overlap on the audio track: order them by `start`, each
  starting no earlier than the previous clip's end; omit `start` to append
  after the prior clip.
- Fields match the source kind: only audio sources go on `--audio-clip`;
  `duration` applies only to image clips; keep `trim` within the material's
  real bounds rather than guessing durations.

## Download checks

When the user requested a file:

- choose an explicit destination and avoid unexpectedly overwriting an existing
  file;
- inspect the byte count returned by the CLI; a zero-byte or clearly implausible
  file is not a valid delivery;
- record the SHA256 returned by the CLI and compare it explicitly when the user
  supplies an expected checksum;
- inspect the actual file content when its format matters; do not rely on the
  extension alone.

## Handoff

Give the user access to the result and any necessary unresolved items. A simple
task usually needs only a canvas link or output. Retain the following identities
and recovery details as needed for continuation, diagnosis, or file delivery;
there is no requirement to display all of them:

- canvas/project identity;
- final node/timeline identity;
- selected Resource IDs;
- downloaded paths and the SHA256 returned by the CLI when requested;
- remaining alternatives or unresolved items;
- the per-run operationRef (= submitId) for resuming the same work.
