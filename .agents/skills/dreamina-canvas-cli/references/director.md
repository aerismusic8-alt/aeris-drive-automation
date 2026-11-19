# Director Stage

## Availability

Director Stage is available where the service has enabled it for the signed-in region. Service code `20078` means the service has not enabled Director Stage for this region. When this happens, nothing was read or changed: tell the user Director Stage is not available in their region yet, and do not retry or work around it. Other canvas commands still work.

Director Stage uses the same eligibility as every other CLI command, so commands that only touch local files also require sign-in and a network connection. When a command returns `vip_membership_required`, tell the user an active VIP membership is required and that nothing was read or changed; do not retry or switch to another way of creating or rendering offline.

## Canvas delivery requirements

When the user wants to create or edit a Director Stage on a canvas, deliver an editable stage on that canvas. Prefer commands with `--project-id` and `--node-id`; use the user's specified canvas or the already selected project. If neither is known, establish the target before writing.

Local files may be used for authoring and previews. After the final local edit, run `director push --file scene.json --project-id <uuid>`, then read the saved stage with `director show --project-id <uuid> --node-id <id>`. Every later local edit needs another push before canvas delivery. A local MP4 or a locally allocated `nodeId` does not prove that the stage was saved.

Before reporting completion, check the save receipt for the target `projectId`, a nonempty `versionId` and a positive `savedDraftVersion`. Read the node back from the same account, profile, region, environment and project; verify its saved version and the final scene/keyframes. Give the user the canvas URL and stage node ID. Use the `webUrl` returned by create, apply, push or show (or by the canvas commands); never construct it yourself.

If saving or readback fails, retain the work file and any `operationRef`, report that canvas delivery is incomplete, and follow the recovery workflow below. Do not silently substitute local video delivery or create another stage to bypass the failure. Upload an exported image/video to the canvas only when that is part of the requested delivery; it does not replace saving the editable stage.

## Discover and author

The full `schema` lists `director` as one entry with a `detailCommand`; run `schema director` for its subcommands. Then inspect `director catalog --kind builtin`. Use only returned primitives, preset IDs and commands. `commandFields` lists each command type's fields with type, required flag, allowed values and structure notes; check it before using a command without an example. its `rendering.available` tells you whether this machine can preview or render. Create, inspect, edit, validate, catalog and FBX operations run in the installed CLI, without Chrome, Node or a source checkout. Preview, image/video rendering and evaluated-frame freeze need local Chrome/Chromium or Edge with working WebGL; MP4 also requires browser H.264 encoding. These commands do not use server rendering or need the canvas page open.

Use `director create --project-id <uuid> --title "Scene"` to create a real editable canvas stage. Inspect with `director show --project-id <uuid> --node-id <id>`. Apply an ordered JSON command array with `director apply --project-id <uuid> --node-id <id> --input commands.json`. Each direct edit reads the current version and saves using a version comparison; it never silently overwrites concurrent edits.

`director create` always creates the stage on the canvas first. Add `--file scene.json` to also keep a new work file bound to that node; then use `director show --file scene.json` and `director apply --file scene.json --input commands.json`, and push to publish those local edits. A failed batch leaves the file unchanged.

Commands cover objects, groups, cameras, environment, poses, motions, property keys and storyboards. `workspace.performance` creates/replaces a performance from staging; use it only intentionally. Each direct canvas read starts in staging: to edit an existing performance, begin the array with `workspace.select`. Presets are fixed catalog entries. Units are meters and XYZ Euler degrees; timeline values are integer display frames.

Prefer the default `linear` interpolation for object motion and camera movement. New `camera.keyframe` / `keyframe.set` keys default to `linear`. Editing an existing key without `interpolation` preserves its curve. To switch it to linear, explicitly pass `interpolation: "linear"`.

Express speed through keyframe timing and value changes. Over equal time intervals, increasing displacement produces acceleration, decreasing displacement produces deceleration, and equal displacement produces constant speed. For example, to accelerate upward, set `position.y` to 0, 0.1, 0.4, 0.9, and 1.6 meters at frames 0, 6, 12, 18, and 24, all using `linear`. Plan camera positions and targets in the same way. For finer speed changes or turns, add keys where motion changes noticeably, then play continuously across the keys and adjust their density based on the result.

Choose `smooth` only when a pause, eased start, or eased finish is intended. Without explicit tangents, `smooth` eases in and out at both ends of each segment. Repeating it throughout continuous motion produces repeated slowdowns and restarts. Linear interpolation also requires deliberate waypoint spacing and timing. Sparse keys or large changes in speed or direction between adjacent segments can still cause abrupt motion.

```json
[
  {"type":"object.primitive","primitive":"cube","id":"prop","name":"Prop"},
  {"type":"workspace.performance","copyStaging":true},
  {"type":"timeline.set","durationFrames":60},
  {"type":"keyframe.set","id":"prop","channel":"rotation.y","frame":0,"value":0},
  {"type":"keyframe.set","id":"prop","channel":"rotation.y","frame":60,"value":180}
]
```

Official assets use `director catalog --kind character|motion`. Follow `nextOffset` while `hasMore` is true. References contain stable IDs, never signed URLs. A local motion library is separate from the canvas body: retain the work file for cross-device rendering. Unsupported local media fails explicitly.

For walking or running along position keyframes, first use `director catalog --kind motion --motion-usage path-traversal`. This searches the full catalog; `offset/count` paginate matching results. Use `direct` for ordinary performance actions. Do not select a path gait just because a name contains “walk”, or relabel a direct action as path traversal. `motion.add` fills the selected official asset’s usage and stride calibration. Omit `motionName` so Web resolves the catalog name in its current language; set it only for an explicit custom label. Path gaits use in-place animation driven by traveled distance. Set `loop: true`, cover the movement interval with the clip, and enable the character’s `pathFacingEnabled` when appropriate. Inspect continuous playback at starts, turns, stops and action transitions; still images cannot prove the absence of foot sliding.

## Place objects and organize groups

Coordinates use meters with Y pointing up. Before moving an existing object, use `director show` to read its `placementAnchor`, optional `pivotOffset` and complete `transform`. Objects created with `object.primitive` or `object.preset` use `bottom-center-v1`, which places the local origin at the center of the model's bottom bounds. For an upright object with positive scale, no custom pivot, and a horizontal surface at world height H, set `transform.position.y` to H. Ground level is 0. A tabletop at 0.8 m requires Y = 0.8, with no extra half-height offset. Choose X and Z within the supporting surface.

`object.set` replaces each supplied top-level field. When changing position, copy the complete `transform` from `show`, edit the desired coordinates, and send position, rotation and scale together. The following example creates an upright prop with its bottom at 0.8 m. It assumes a supporting surface already exists at that height.

```json
[
  {"type":"object.primitive","primitive":"cube","id":"tabletop-prop","name":"Tabletop prop"},
  {"type":"object.set","id":"tabletop-prop","patch":{"transform":{"position":{"x":0,"y":0.8,"z":0},"rotation":{"x":0,"y":0,"z":0},"scale":{"x":0.2,"y":0.2,"z":0.2}}}}
]
```

`object.ground` with `ids` resets Y to 0 for eligible, unlocked models using `bottom-center-v1`. Other objects can remain unchanged, so read back the result. For placement on another object, determine the supporting surface's world height and use `object.set`. Objects with a missing or different `placementAnchor`, tilted or inverted objects, animated poses and sloped surfaces require checking their actual bounds and contact points. Inspect the preview for gaps, intersections and overhangs, then adjust and inspect again.

Use `group.create` with `id`, `name` and at least two member `ids` to save a selection group. Members retain their individual transforms and animation tracks. Apply movement to the member object IDs.

## Merge parts for shared animation

When several parts should move together, use `object.merge` with their `ids`, a new `id` and a `name`. At least two distinct objects are required. Their world placement is preserved, and the merged object's origin is the combined bottom center. The parts become private components. Use the new ID for subsequent transforms and keyframes. Merging runs in the installed CLI without a browser.

Supported sources are primitives, procedural presets and composites containing only those sources. Members must be visible, unlocked, non-rigged and free of motion clips and property keyframes. Imported models and unsupported members fail the entire apply batch, preserving the original content. Build and merge parts before adding animation. For an existing performance, select its workspace and inspect the current objects first.

```json
[
  {"type":"object.primitive","primitive":"cube","id":"body"},
  {"type":"object.primitive","primitive":"sphere","id":"detail"},
  {"type":"object.set","id":"detail","patch":{"transform":{"position":{"x":1,"y":1,"z":0},"rotation":{"x":0,"y":0,"z":0},"scale":{"x":0.2,"y":0.2,"z":0.2}}}},
  {"type":"object.merge","ids":["body","detail"],"id":"assembly","name":"Assembly"},
  {"type":"workspace.performance","copyStaging":true},
  {"type":"keyframe.set","id":"assembly","channel":"rotation.y","frame":0,"value":0},
  {"type":"keyframe.set","id":"assembly","channel":"rotation.y","frame":30,"value":90}
]
```

This example creates a performance for the assembly. Read back with `show` to verify the new object and its tracks, then preview the motion to check the entire assembly and its pivot.

## Set a custom pivot before animation

Use `object.pivot` with `id` and `offset: {x,y,z}` to set an absolute local-meter offset from the object's placement-policy origin. For a bottom-centered object, `{x:0,y:1,z:0}` moves the pivot one local meter upward. Repeating the same offset has no cumulative effect. `{x:0,y:0,z:0}` restores the placement-policy origin.

The command compensates position so the rendered object stays in place, including existing rotation and nonuniform scale. Subsequent rotation and scale use the new pivot. `transform.position` now locates that pivot in world space. For an upright bottom-centered object on a horizontal surface, set Y to the surface height plus `pivotOffset.y * transform.scale.y`, or use `object.ground` for the ground plane.

Set the pivot before adding animation. The target must be a visible, unlocked, non-rigged model without motion clips or property keyframes. This includes supported merged objects. A rejected command rolls back the entire apply batch. Use `show` to verify the offset and compensated position, then preview the motion.

```json
[
  {"type":"object.primitive","primitive":"cube","id":"door","name":"Door"},
  {"type":"object.pivot","id":"door","offset":{"x":-0.5,"y":0,"z":0}},
  {"type":"workspace.performance","copyStaging":true},
  {"type":"keyframe.set","id":"door","channel":"rotation.y","frame":0,"value":0},
  {"type":"keyframe.set","id":"door","channel":"rotation.y","frame":30,"value":90}
]
```

Custom pivots require a compatible canvas reader and backend. Older canvas versions reject these scenes. Use a compatible version to view or edit them.

## Inspect visually and iterate

After initial blocking and after every important scene/camera change, call `director preview --project-id <uuid> --node-id <id> --workspace performance --storyboard --frame 30`, or `director preview --file scene.json --camera-id scene-camera`. Choose `--camera-id` or `--storyboard`, not both. Omitted `--output` creates a new managed PNG. Open the returned absolute `path` using your image-viewing tool; JSON success alone is not visual inspection.

The result identifies `source.nodeId`, baseline `source.versionId`, `source.contentSha256` and render `options`. Local changes can differ from the baseline version; the hash includes the exact document, motion library and session. `--workspace staging|performance` selects this render only. Preview never changes the canvas.

Inspect composition, scale, occlusion, spatial relationships, character blocking and camera direction. Sample the start, middle and end of each shot and both sides of cuts. Apply small typed edits, preview again, and inspect the new image. Render a short video when still frames cannot establish motion continuity. Use simple humanoids or preset characters; prioritize abstract sets, blocking and camera movement when reverse-engineering a reference video. Detailed appearance and character animation are secondary to usable generation references.

Without browser/render support, continue data authoring and report the missing visual check. Preview, image/video export and freeze then fail with `error.code=40022`. If the error includes `canvasHandoff`, give the user `canvasHandoff.webUrl` and `canvasHandoff.nodeId`, and ask them to open that Director Stage on the canvas and export the image or video (or freeze the frame) there. The canvas shows the last pushed version, so push local edits first. If there is no `canvasHandoff`, the work file has not been saved to the canvas yet: push it and retry to get the link. Never claim that the export exists until the user confirms it. Without image-viewing support, hand the preview path to a capable user/Agent; never claim you saw it. Missing rendering support does not prevent data edits or create empty canvas nodes.

## Synchronize and recover

Use `director push --file scene.json --project-id <uuid>` to publish a local stage. Push keeps the canvas node name unless you changed the title with `document.title`. `director pull --file fresh.json --project-id <uuid> --node-id <id>` reads a stage into a new file. Work files are bound on publication to the account, profile, region, environment and project. Internal production writes remain blocked; public writes remain subject to server authorization.

Direct create/apply returns a `file` (managed, or the `--file` path for create). If a failed direct write returns `operationRef`, pass it to `director push --file <operationRef>`; do not repeat create/apply and generate a new write. For interrupted push, repeat the same push. Keep `pending`, `writeId`, `updateId` and the body unchanged. A conflict (`error.code=7`) with `directorConflict` identifies a changed canvas version: pull `directorConflict.latestVersionId` into another file and replay intentional edits. Use `push --force` only when the user explicitly wants this file to replace it, and tell the user the `overwrittenVersionId` from the receipt. The `.lock` next to a file is released when its command exits, even if interrupted; do not delete it. `error.code=40020` means another command is still running on that file.

## Export and deliver

Local delivery: `director export --file scene.json --type image --output shot.png` or `--type video --workspace performance --output film.mp4`. You can use `--project-id <uuid> --node-id <id>` instead of `--file`. `--frame` selects an image frame; `--long-edge` is 1280 or 1920. Output paths must be new. Results include size, SHA-256, source and options.

Canvas delivery: `director export --project-id <uuid> --node-id <id> --workspace performance --type video --storyboard --to-canvas`. For PNG, select `--type image` and a frame. `--to-canvas` manages its own file, so do not pass `--output`. It renders locally, uploads through the existing media pipeline, registers a resource and creates a real image/video node. Verify `canvas.nodeId`, `canvas.resourceId` and `canvas.savedDraftVersion`, then use `node show` to inspect the saved result. The original stage stays editable. If a work file has edits that were not pushed, exporting it with `--to-canvas` returns `error.code=7` with the unsaved-source cause; push first.

If delivery fails, run `director resume-export --operation-ref <path>` using the returned reference, not a fresh export. Recovery freezes the source, parameters, artifact and resource/node identities. It resumes completed stages and returns the same receipt after success. Account/environment changes and modified artifacts are rejected. Never share private storage handles from recovery files. Director recovery paths are not generation-task IDs for `operation status/wait`.

If the error identifies an unverified original region (`code=40003`), the original region of the work file or export record cannot be verified, even if it contains a completed receipt. Stop automatic recovery, keep the original files, and do not edit their region fields. Check the existing result on the original canvas, using `node find` to locate nodes or `node show` when the node ID is known, before deciding how to proceed. Do not automatically repeat the save or export.

## Motion files and evaluated frames

`director freeze --file scene.json --frame 30` copies an evaluated performance frame into staging and requires the renderer. Import motion JSON with `motion.import` (`id,file`) or FBX with `motion.import-fbx` (`id,name,contentBase64`). Export with `director export --file scene.json --type fbx --motion-id <id> --output motion.fbx`; this runs without a browser. FBX contains animation and cannot be delivered as an image/video canvas node.
