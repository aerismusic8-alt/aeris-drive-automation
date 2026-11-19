# Post-edit guidance

Inspect `node show` or `resource get` first. Image/video media fields are optional; missing is unknown, never zero.
Video `fps` follows the existing resource query contract, which may describe a delivery rendition; `effectiveFps` also accounts for a successful interpolation target. The server uses authoritative original metadata for execution eligibility.
Submit `node upscale video --resolution 2K|4K`, `node cutout image`, or `node interpolate video --fps 30|60`, each with `--node-id`.
Omit `--title` by default. An explicit title is a complete override requested by the user.
These commands execute on submission; they do not accept `--run`. `--dry-run` checks local input only.

Discover video upscaling models with `model upscale --kind post_edit --type video`; for image upscaling, use `model pro_hd --kind post_edit --type image`.
Pass a canonical value from the `model_name` parameter enum through `--model`. Video uses `node upscale video --model <model> --resolution 2K|4K`; image model selection uses the [image upscale credit workflow](credits-and-hitl.md#image-upscale-uses-its-own-approval-scope).
Omitting the video model keeps the default model. The directory may list resolutions across several models; the quote validates the selected model, resolution and source together. All items in one batch use the same explicit model.

Use repeatable unique `--node-id` values (1..20) for one operation and target per batch.
Provide matching unique `--submit-id` values in the same order or let the CLI allocate them.
When confirmation is required, approve the whole batch ceiling through the existing credit workflow. Tokens are operation-scoped.
Never treat an unknown/blocked quote as zero credits or automatically remove rejected members and spend on the remainder.
The server revalidates the current source and eligibility at quote, confirm and the first run.
Read typed `preflight` facts and optional `diagnostics[].detail` causes; do not parse message text or submit client-reported media facts.

A 30 FPS source may qualify for 60 FPS if entitlement and other checks pass; 30 FPS to 30 FPS is blocked.
The existing 1 FPS tolerance treats 29/59 FPS as already reaching 30/60 FPS.
Accepted submissions can finish later. Preserve every submitId and use `operation status` or `operation wait` after interruption or an UNKNOWN result.
Do not automatically generate another submitId. Batch run is not atomic; recover each output independently.
If the service explicitly rejects credit approval before admission, rerun the same post-edit command with the original submitIds and unchanged parameters. The CLI re-quotes and re-confirms within the original known credit ceiling. An opaque expired token requires a renewed post-edit token or an explicitly approved ceiling; never infer or increase its ceiling. A timeout, disconnect, UNKNOWN result, or ABSENT status does not authorize resubmission.

## Free member interpolation

When a quote or submission explicitly identifies the operation as unavailable in the current region, do not retry or request credit confirmation. Already accepted submissions keep their existing recovery path.

For a valid member and eligible source, a complete ready quote with zero credits and `confirmationRequired=false` skips the credit prompt and confirmation endpoint.
Use `node interpolate video --node-id <nodeId> --fps 60 --wait` without a default credit ceiling or token.
An explicit `--credit-ceiling 0` still uses the existing zero-ceiling confirmation branch.
Never infer eligibility from a zero amount: blocked, unknown, missing, or failed quotes stop before submission.
The server rechecks membership and the required free benefit at execution; unavailable free benefits must not fall back to paid generation.

## Depth motion capture

Use `node depth-capture video --node-id <nodeId> --wait` to create a grayscale depth video from one ready video node up to 30 seconds long. The output short edge defaults to 480p; use `--resolution 720p` for 720p. Follow the quoted credit requirement. Once generation succeeds, use the returned output `nodeId` as a regular video reference in supported modes.
