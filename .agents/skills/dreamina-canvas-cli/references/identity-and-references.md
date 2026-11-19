# Identity and references

Use this reference when deciding what identity to persist or how a downstream
node should consume upstream material.

## Choose the source before its output

For an existing source node on the target canvas, use its Node ID for downstream
generation, Element bindings, and timeline clips. Do not read or copy its
Resource ID just to build a reference, even after generation succeeds. Node
references preserve upstream edges and use the source's selected output;
Resource references freeze material without inferring a source-node edge.

| Use | Default for an existing canvas source |
| --- | --- |
| Image/video generation, including first/last frames | `--ref node:<node-id>` |
| Media placeholder in a prompt | `{{node:<node-id>}}` |
| Element primary/voice/auxiliary slot | `--main <node-id>`, `--voice <node-id>`, `--auxiliary <node-id>` |
| Timeline visual/audio clip | `--clip <node-id>,kind=canvas_node`, `--audio-clip <node-id>,kind=canvas_node` |

Resource IDs returned by a node identify concrete outputs for resource status
and metadata queries, downloading, and recording a chosen result. Operation
polling itself uses `operation status|wait <submitId>`; it does not require the
Agent to extract a Resource ID from the node first.

Use resource references only for asset-library/uploaded material without a
source node, or when the user explicitly requires a fixed output that must not
follow later selection. If that exception applies, record the reason and selected
Resource ID; otherwise keep the Node ID. Once an imported resource has a canvas
node, prefer that node for downstream work. Consistency, successful generation,
or the mere presence of `resources[]` is not a reason to freeze.

When checking reference structure or diagnosing links, use the saved-source and
upstream-edge checks in [completion-and-validation.md](completion-and-validation.md).
Generation without references does not need these checks. A successful
generation or a reference thumbnail does not prove a node link exists.

## Public identity model

Generation references use four explicit protocol discriminators; only two currently resolve to objects.

| Identity | Written form | Meaning | Use when |
| --- | --- | --- | --- |
| Node ID | `node:node_xxx` | A canvas node whose selected media output or Text content may change | default for an existing canvas source; retains upstream edges |
| Resource ID | `res:<resourceId>` | One concrete material result | no source node, or explicit user-requested freezing; no inferred node edge |
| URI / VID | `uri:<value>` / `vid:<value>` | Reserved protocol values, not resolved yet | schema-level expression only |

Generation flags and prompt placeholders use `type:value` / `{{type:value}}`.
Subject elements and timeline selectors keep their existing bare Node ID / Resource ID contracts;
they are not part of this generation reference protocol.

Anything else is rejected **locally** with an invalid-input exit; no request is sent:

- `uri` and `vid` are accepted as typed protocol values, but the server explicitly returns
  unsupported; they must not be treated as access capabilities or resolved locally.
- A Resource ID accepts a canonical lowercase UUID or the workflow-returned `resource_<positive integer>[-<nonnegative index>]`; index 0 is valid.
  Preserve the returned identity; do not add prefixes or convert it to a UUID. Uppercase UUIDs,
  `urn:uuid:` prefixes, and dash-stripped UUIDs are rejected. Project IDs and upload creation keys remain UUIDs.

The server still owns existence, type, state, project relationship, and authorization: a valid
written form only means the spelling is right, not that the material is usable.

## Resolution rules

1. Every dereference is evaluated for the authenticated actor and target
   canvas/project.
2. Unauthorized, missing, or no-longer-linked material must not be treated as a
   usable reference merely because its ID is known.
3. A Node ID used by an Element binding must belong to the target Element's canvas. A cross-canvas,
   missing, or unauthorized Node ID receives the same public error shape.
4. Saving a Resource requires an active target-project link. If that link is missing,
   use the explicit source input described below; knowing the Resource ID is not enough.
5. A syntax or capability hint is not an authorization snapshot.
6. Temporary access material is for immediate in-memory consumption only and is
   never a durable identity.
7. What you reference decides when the terminal state is checked. A `res:` (Resource ID)
   reference requires a successful terminal state and is rejected at **save time** while the
   material is still generating; a `node:` (canvas node) reference **may point at an
   upstream node that is still generating**, and its terminal state is checked at **run
   time**. So to build on an output that has not been produced yet, reference its node
   (`node:node_xxx`) rather than a Resource ID it does not have yet. Text context does not
   require a generated Resource; its source node must be accessible and its content readable
   (accessibility and readability are enforced mainly at run time).
   Exception: a timeline clip (`--clip` / `--audio-clip`) cannot reference material that is
   not ready yet — even when it uses a Node ID, the referenced node must already have
   generated successfully and have a usable output, or saving the timeline is rejected.
8. "Does not exist", "no permission", and "already unlinked" all return the **same** error and
   are deliberately indistinguishable. Do not infer whether an ID exists from an error code.

## Upload material identity

> Applies only to artifacts whose schema advertises `resource upload`; skip this section when it is
> absent from `schema`.

Always pass `--project-id` to `resource upload`, even with `--resource-id`. The Resource ID
is a retry identity, not a way to choose the upload project.

After the upload identity is fixed, failures retain `error.resourceId` and `error.projectId`. These identify the attempted operation; they do not prove that storage or registration succeeded. Preserve them after a lost response, inspect the original resource where possible, and do not automatically upload again under a new ID. Code `40012` means the outcome is unconfirmed, not a definite rejection.

Artifacts that register `resource upload` expose it through `schema`; local-file upload is a gated runtime
capability that not every such artifact composes. When it is not composed, the server's admission decision is
authoritative. Local image, video, and audio files use direct upload before registration. Image `--source-url`
input is fetched and stored by the service. Every result carries `resourceId + mediaType` regardless of
`--import-kind` and does not expose a server-side storage handle.
Use the `resourceId` with `res:<resourceId>`, `resource get/download`, and `node create --resource-id`.
When you import a registered resource with `--resource-id`, you must also specify `--import-kind`
with the same registration intent vocabulary:
`local_upload` for locally uploaded material or `external_generated` for externally generated output.
Either value may also be declared without a Resource. `--resource-id` accepts either import kind. The kind is
consumed as creation intent and is not persisted in the draft. Position is independent of import kind.

That same `resourceId` is the input to `node create image|video|audio --resource-id`, which declares at
creation time that these registered resources belong to the node, so the node lands already carrying its
media. This is how uploaded or externally generated media is imported into the canvas while keeping the
originating prompt and model parameters for further edits and re-generation. Multiple resourceIds form
candidates within one batch — declaration order is candidate order, and the first is primary. Only `create`
accepts the flag, and only media node types accept resource declarations. `text`, `element`, and `timeline`
can also specify the same `--import-kind` values, but cannot specify `--resource-id`.

Ownership, status, and type match are adjudicated server-side and are rejected rather than silently dropped;
node source remains server-materialized and cannot be specified by the caller.

The batch identity comes from the same command's `--submit-id` (generated when omitted): reusing the same
value on retry keeps the batch identity stable. This is the only case where `--submit-id` works without
`--run` — imports take the save-only path but still need a submission identity.

## Node placement and spacing

`--x --y` are optional: omit them by default. Specify coordinates when the task needs a particular position or layout,
such as moving nodes, arranging the canvas, placing external imports, or preserving the layout of a recreated canvas.
An external import with no placement requirement can also use smart placement.
All six `node create` and `node edit` types support them, including imports. If specified, both values must be provided
together and be finite; zero and negative coordinates are supported. An explicit position takes priority over smart placement
on create but does not automatically avoid existing nodes. On edit, you may change position alone or together with content.
Omitting both coordinates preserves smart placement on create and the existing position on edit. Moving a timeline preserves its tracks.

When the task calls for explicit placement, use the nodes' actual saved dimensions:

1. Read `layout.x/y/width/height` and `parentNodeId` from the save result's `data.node` or a FOUND item in `node show`.
   When a new node's dimensions are unknown, create it with smart placement and query it before moving it as needed for the task.
   Do not assume equal node sizes.
2. Leave horizontal spacing `gapX` and vertical spacing `gapY` between node rectangles in the same coordinate space.
   For a row, use `nextX = x + width + gapX`; for the next row, use `nextY = rowY + max(rowHeights) + gapY`.
   Start with `gapX = 160` px and `gapY = 80` px, then adjust for actual dimensions.
   Image ratios vary, and timelines can be much wider; read back after saving to check the layout.
3. Compare coordinates directly only for nodes with the same parent; root nodes share canvas coordinates.
   Convert coordinates to canvas space before comparing nodes across groups. A group containing its children is expected;
   do not treat that containment as overlap to remove or change group membership for spacing.
4. Read positions and dimensions again after editing to confirm that unintended overlap is gone and content and group membership remain intact.
   Recheck with fresh dimensions when generation or content edits change the size. Omit `--run` when only moving nodes.

When recreating a canvas in another project or region and the task calls for preserving its layout, read every source node with `node show` and reuse
`node.layout.x/y` for the destination node's `--x --y` when the source is a root node. If `parentNodeId` is
present, its coordinates are relative to that group: add the parent group position before creating a root node
in the destination. Editing uses the same coordinate space returned by `node show` and preserves group membership.
`parentNodeId` is read-only. Use `layout.width/height/zIndex` to inspect and check the layout;
they are not create or edit inputs.

## Prompt references

Generation references use the explicit forms above. `node` and `res` are the usable public identities;
`uri` and `vid` remain reserved protocol values and are not upload-result capabilities.

Prompt references serve two different purposes; keep them separate:

- `--ref node:<node-id>` adds the source node to the generation reference set,
  supplying a material slot, order, and upstream edge.
- `{{node:<node-id>}}` binds the source node to that exact prompt position,
  equivalent to an object @ mention in the product prompt. Use the stable public
  placeholder; natural-language names or manually typed `@name` text do not
  establish a node reference.

When a prompt describes several reusable characters, objects, or environments and
they occupy different actions, positions, or relationships in the sentence, prefer
`{{node:<node-id>}}` at the relevant words. Appending the same nodes only through
`--ref` builds a reference set and canvas provenance, but it does not bind a
specific node to an object and its action, position, or relationship in the text.

The following is an argument fragment. Replace `node_a` and `node_b` with actual
Node IDs whose types have been checked against the selected mode, and supply the
remaining fields required by the current schema:

```bash
--mode i2i \
--prompt "Place {{node:node_a}} on the left and {{node:node_b}} on the right" \
--ref node:node_a \
--ref node:node_b
```

If the same node appears in both a prompt placeholder and `--ref`, it is merged
into one reference slot. Read the saved `generation.references[]` for the final
slot order; do not infer it from flag order alone. Prompt placeholders do not
replace mode-specific slot configuration such as first/last frames.
If the node is only an additional style
reference, background reference, or leading Text context, it may remain only in
`--ref`. Text nodes still follow the restriction below and must not be used as
prompt placeholders.

Reference order may be meaningful for first/last frame, primary/auxiliary
material, or model-specific slots. Preserve the order returned by the user's
plan and the model schema.

Reading a node back returns the prompt in the same public placeholder form you
wrote — write `{{node:node_xxx}}`, read `{{node:node_xxx}}`. That round trip is the reason the read-back result is
directly usable as the next write input, and also the reason a Resource ID has only one
accepted spelling: accepting equivalent forms such as uppercase or `urn:uuid:` would force the
read-back to emit the normalized one, and verbatim closure would be lost.

Read the prompt from the node's `generation`, never from the opaque canvas draft
body also present in the response. `generation` is absent for non-generating nodes.
Its `references` list is the slot order, so read it to confirm the final order
whenever you mixed prompt placeholders with explicit reference flags.

### Video mode follows the resolved source type

Never select a frame mode merely because there is exactly one Node reference. A `node_` prefix identifies
a canvas Node but does not reveal whether that Node is an image, Element, Text, video, or audio.
Inspect the referenced Node or Resource first, then select the public mode from the resolved material
type and the live model capability:

| Resolved generation material | Public `--mode` | Constraint |
| --- | --- | --- |
| No media material | `t2v` | Must not carry a media reference |
| Exactly one image used as a locked-ratio first frame | `first_last_frame` | The image occupies the first-frame slot and determines the output ratio |
| Two ordered images | `first_last_frame` | Order is first frame, then last frame; both original ratios must match |
| One image with a caller-selected output ratio | `m2v` | Use a compatible multimodal model |
| An Element node or mixed multimodal material | `m2v` | Use a compatible model returned by live model discovery |

An Element remains a typed Node reference. Pass it as `--ref node:<element-node-id>` with `--mode m2v`:

```bash
--mode m2v \
--ref node:node_element \
--prompt "Animate {{node:node_element}} in the described scene."
```

`m2v` is the public CLI spelling of multimodal mode. Server-side generation specs may use
`multi_modal`, but `multi_modal` is not a valid value for the CLI `--mode` flag. An Element must not
occupy a `first_last_frame` frame slot.

### Text nodes are context-only references

Text is not an image/video material, but it can supply prompt context through
`--ref node:<text-node-id>` when the selected mode permits it. It must not appear as a
`{{node:<text-node-id>}}` placeholder in the prompt. Both image and video saves enforce this
restriction, including mixed inputs that also contain valid image references.
Inspect the source node's type before using a Node ID as a prompt placeholder: the `node_` prefix
alone does not distinguish Text from media.

At run time, referenced Text content is read and prepended to the prompt as context. It does not
occupy a media slot or expand at a chosen position in the prompt. Still satisfy the selected
mode's `--prompt` and reference requirements.

Reference placement and mode must be considered together:

Generation modes use short protocol names. Their full meanings are: `t2i` = text-to-image,
`i2i` = image-to-image, `t2v` = text-to-video, `m2v` = multimodal-to-video, plus
`first_last_frame` (first/last frame) for video and `tts` (text-to-speech) / `music` for audio.
Image-to-video is not a public CLI mode: for single-image video use `first_last_frame` (one
first-frame image), and for image- or video-guided generation use `m2v`. The server may report
internal spellings through model discovery, but the CLI always normalizes them back to these
public names.

| Input | Reference rule |
| --- | --- |
| Image `t2i`: Text in `--ref`, ordinary prompt | Valid context form; no image material is required. T2I does not mean the reference list must be empty. |
| Image `i2i`: only Text in `--ref` | Rejected: Text cannot satisfy I2I's requirement for at least one image, Element, or image Resource. Use `t2i` for Text-only context. |
| Image `i2i`: image and Text both in `--ref`, ordinary prompt | Valid mixed form: the image supplies material; Text supplies context. |
| Image `t2i`: an image, Element, or Resource reference | Mode mismatch; use `i2i` for image material input. Adding Text does not make this T2I. |
| Image/video: Text inside a prompt placeholder | Rejected, even if the same Text is also in `--ref` or valid image material is present. |
| Video `m2v`: image material plus Text in `--ref` | Valid context form, subject to the selected model's material and parameter requirements. |
| Video `t2v`: any reference | Rejected by the current CLI, including Text in `--ref`; do not copy the image T2I rule to video T2V. |

Video `first_last_frame` requires one or two merged references. Adding Text consumes an entry in
that check even though it
is not a media material; it cannot replace a frame. Do not blindly add Text to every video mode.

Valid forms above describe the reference contract, not a guarantee that a particular model,
release, or environment will save or run successfully. Source access, media readiness, and model
constraints still apply. Distinguish protocol checks from an actual end-to-end verification.

Argument fragments below use `node_text` and `node_image` for actual Text and image Node IDs
that you have already inspected. Supply the other required command fields separately.

Text-only context for an image:

```bash
--mode t2i --ref node:node_text --prompt "Create a poster using the reference text."
```

Image material and Text context, both passed through the reference list:

```bash
--mode i2i --ref node:node_image --ref node:node_text \
--prompt "Edit the reference image according to the reference text."
```

For mixed Text and image video input, only the image may appear in the prompt placeholder:

```bash
--mode m2v \
--ref node:node_text \
--prompt "Animate the scene in {{node:node_image}}."
```

If exact inline wording is required, write that wording as ordinary prompt text instead of a Text
node placeholder. Copied text no longer follows later edits to the source node; do not also add
the same Text reference unless its content is intended to appear again as leading context.

### Diagnose reference rejection without guessing

`error.code=2` means invalid parameters; it does not prove that Text is universally unsupported or that the generation model rejected the request. Optional `diagnostics[].detail` can explain the specific input and constraint. Read it to understand the cause, but do not parse its wording or dynamic values for automated decisions. Read counts, durations, and model limits from `model list`, quote results, or typed preflight facts. If details are absent, do not invent a cause from `message`; retain `meta.requestId` for diagnosis when present.

The following table is for manual diagnosis only, not a stable machine contract:

| Original diagnostic, when available | Meaning and correction |
| --- | --- |
| `i2i requires at least one image, subject, or resource reference` | No real I2I material was provided. Text-only context belongs in `t2i`, or add suitable image material. |
| `text canvas reference must not appear in the prompt; pass it through the reference list only` | Remove the Text placeholder from the prompt and keep Text in `--ref`; the mode must still allow the remaining inputs. |
| `t2i accepts only Text canvas references` | The T2I input contains non-Text material. Select `i2i` for that material instead. |

The server validates public reference identity syntax, then resolves actual node types and validates
mode/material and prompt-placement semantics at save time. A server error response does not imply
that Text was rejected through a node-type whitelist, or that generation was dispatched.

Without `--run`, `ok=true`, saved prompt parts, and upstream edges prove a successful save only,
not media generation. Verify execution and terminal Resource results separately when requested.

## Image and video generation edits

For `node create|edit image|video`, explicitly supply a non-empty `--mode` whenever you supply
any generation field: `mode`, `prompt`, `model`, `ratio`, `resolution`, `count`, `ref`, or video
`duration`. There is no default mode, and edit does not inherit the saved mode. Missing or empty
mode is rejected locally with `error.code=2`, a specific cause in `diagnostics`, and exit code 2.

Generation is a complete replacement, not a field-level patch. Read the saved `generation`
first when retaining its prompt or references, then submit the complete intended input, including
mode and the intended prompt. A visual draft may have empty text if the model specification
permits it; save success does not prove it is runnable. The server checks the projected effective text
before run claims or charging. Supply a title for `create --run` if empty text cannot name the node.
Title/tag-only changes, `--clear-tags`, and `--clear-generation`
alone do not require mode. Do not combine `--clear-generation` with generation fields.
Adding `--run` does not change these input rules.

## Audio model and voice selection

See [Model and voice discovery in the main Skill](../SKILL.md#model-and-voice-discovery)
for commands, output fields, and pagination examples.

Choose a currently available workflow for the task. The table contains argument fragments;
add required inputs such as `--project-id` and a nonempty `--prompt` when creating or editing.
All audio workflows produce one output; omit `--count`.

| Purpose | Generation arguments | Voice and references |
| --- | --- | --- |
| Voice-based speech without selecting a model | `--mode tts --voice-name <voiceName>` | Choose from this workflow's voice catalog; omit `--model`, `--scenario`, `--duration`, and `--ref` |
| Speech with a model that has no scenarios | `--mode tts --model <model> --voice-name <voiceName>` | Omit `--scenario` when discovery lists none; select a voice from that model's catalog |
| Text reading with a selected model | `--mode tts --model <model> --scenario text-reading` | Choose the required `--voice-id` or a unique `--voice-name` from `voice list --model <model>`; references are not supported |
| Omni dubbing | `--mode tts --model <model> --scenario omni-dubbing` | Optionally choose one `--voice-id` or unique `--voice-name` from the same model catalog and use image, audio, or Element references within the current specification |
| Music generation | `--mode music --model <model> --duration <seconds>` | Choose a model with a `music` mode and an allowed positive duration from `model list --type audio`; omit voice, scenario, and references |

Use the capabilities returned by `model list --type audio`: explicitly select a scenario when the model has scenarios; otherwise omit `--scenario`. For example, a listed `legacy_tts` model accepts the model, text, and its catalog voice. Correct unknown models, unsupported scenarios, or mismatched voices without silently switching selections. `--dry-run` does not verify model capabilities online; check discovery before execution.
Prefer the returned `voiceId` with `--voice-id`; use `--voice-name` only for a unique name. These selectors are mutually exclusive. Use IDs from the same model catalog, never a speaker ID from execution metadata. When a name is ambiguous, inspect tags and select the intended ID; never select the first match automatically. If the service returns no IDs, use a unique name until ID selection is available. Selecting a voice does not play audio or require a separate voice upload.
Retain the selected voice to reproduce the creative decision.

Omni dubbing save example: replace the placeholders with a model and voice you have inspected.

```bash
dreamina-canvas node create audio \
  --project-id <projectId> --mode tts --model <model> \
  --scenario omni-dubbing --prompt "<spoken text>" \
  --voice-name "<voiceName>"
```

Reference identities and prompt placeholders follow [Prompt references](#prompt-references) in this document.
A voice counts as an audio reference and shares the selected model and scenario's `references.max`
and audio type limit with ordinary audio. Also obey `references.mutuallyExclusiveTypes`.
When image and audio are mutually exclusive, an image and a voice cannot be combined.
Use live limits rather than a fixed count, and do not discard references automatically.

When diagnostics identify a material constraint violation, follow [Reference rejection diagnosis](#diagnose-reference-rejection-without-guessing)
to locate the conflict, adjust references or cancel the voice selection, and submit the complete generation configuration.
When an execution outcome is uncertain, query the original operation using [Recovery and idempotency](recovery-and-idempotency.md);
do not create a new submit ID to resubmit. The example only saves the node. To generate audio, follow
[Credit approval](credits-and-hitl.md) and run after approval; save success does not prove audio generation.

Before editing, read the current `generation` with `node show`, retain the intended model, scenario, voice,
prompt, and reference order, then rebuild the complete generation configuration. A single catalog voice not
mentioned in the prompt reads back as `voiceId` and `voiceName`. If the response blocks writeback, such as a Web draft with
multiple voices or inline voice mentions, preserve the draft and edit it in Web. Do not replace or clear its
generation configuration to bypass the restriction; retain it when editing only the title or tags.

## State to retain

For a resumable creative job, retain:

- canvas/project identity;
- stable business key -> Node ID mapping;
- submit ID and operation reference for each run;
- selected terminal Resource ID;
- whether a downstream relation follows a Node or freezes a Resource.

Do not persist undocumented internal identifiers, signed URLs, provider task
payloads, or short-lived confirmation material.

## Cross-project Resource inputs

When a Resource is not yet linked to the target project, add `--resource-source <resourceId>@<sourceProjectId>` to the node create/edit command. Repeat it for each Resource that needs a link; one declaration covers repeated uses of the same Resource, and one save may use multiple source projects. Keep `--ref res:<resourceId>`, `{{res:<resourceId>}}`, imported `--resource-id`, Element bindings, and timeline clips as plain IDs. A declaration does not attach media by itself; conflicting or unused declarations are rejected. Node IDs, text nodes, and read/upload commands do not accept this flag.

The target link is prepared before saving, then `--run` follows the usual quote/approve/run flow. The saved node still contains ordinary Resource IDs. `--dry-run` checks syntax only; it does not check access or create a link. For uncertain save results, follow [recovery and idempotency](recovery-and-idempotency.md).
