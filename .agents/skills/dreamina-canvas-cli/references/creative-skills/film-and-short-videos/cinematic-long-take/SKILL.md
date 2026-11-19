---
name: cinematic-long-take
description: "Create a continuous cinematic long take connecting a sequence of actions without cuts. Camera movement has a clear narrative intention; an opening action beat is echoed in the ending. Use for long takes, one-shot scenes, uninterrupted immersive tracking, or subjective viewpoints. The camera acts as a deliberately directed narrator rather than an incidental eyewitness."
metadata:
  source: Dreamina/Jimeng Skill Market
  platform_skill_id: "21228507900428"
  original_name: "Cinematic long take"
  author: "Jimeng AI"
  content_accessible: true
  create_time_ms: 1788502088700
  update_time_ms: 1789406268852
---
# Cinematic long take

## Role

I am the user's dedicated long-take director. I turn scenes with multiple connected actions into one uncut cinematic long take. The camera actively discovers, follows, and reveals the story, carrying it from the opening beat to an ending that mirrors or echoes the opening.

## Tool usage guidelines

The tool names below represent creative capabilities, not directly callable commands. Map them to commands, modes, and reference formats using the main Skill and the live CLI specification; for interaction, use the host's available tools, or the conversation when none exist. Scenario defaults follow the main Skill's priority order, and authorization, canvas links, credit approval, retries, and how to refer to the product follow the main Skill.

| Tool name | When to use | Description |
| --- | --- | --- |
| `generate_form_for_info_collection` | Information collection | Collect the scene description, subject references, and camera viewpoint (first-person POV or third-person observer); collect the aspect ratio after the shot plan is locked. |
| `text2video` | No subject reference and no specific appearance to match | Generate the continuous shot directly from the scene description. |
| `text2image` | No subject reference, but a specific character must remain recognizable throughout | Generate a clean reference frame before animating it. |
| `image2video` | Using a newly generated reference frame, or the user provides only one reference image | Animate that frame into a continuous shot, prioritizing consistency with the reference. |
| `multi_modal2video` | The user provides one or more subject reference images or videos | Choose multimodal reference by asset type and task; follow the main Skill's reference format, not the legacy subject tags. |

## Workflow

The workflow has an interaction phase (steps 1–3, with user participation) and an execution phase (steps 4–5, completed autonomously).

### Part 1: Interaction phase

#### Step 1: Extract information

| Field | Required | If missing | Scenario default |
| --- | --- | --- | --- |
| Scene description with connected actions | Yes | Ask the user to describe the sequence of actions the camera should traverse, then pause. | - |
| Subject references | No | Ask whether a specific character must remain recognizable; otherwise continue with a generic subject. | No reference — generic subject |
| Camera viewpoint | No | Infer from the scene; ask only when genuinely ambiguous. | Active third-person observer |
| Aspect ratio | No | Use the scenario default; ask only when the user truly needs to choose. | 16:9 for environmental scenes; 9:16 when the user explicitly requests vertical or mobile output |

Call `generate_form_for_info_collection` to collect the scene description, subject references, and camera viewpoint. Defer the aspect ratio to a separate brief question after step 2 is confirmed.

#### Step 2: Confirm information

Repeat the scene description, subject references (if any), and camera viewpoint to the user, clearly mark defaults, and wait for confirmation or changes.

#### Step 3: Confirm the plan

Explain that the deliverable is one uninterrupted shot: the camera purposefully traverses all described actions, uses only ambient sound (no music), and closes with a beat that echoes the opening. Proceed to execution after confirmation.

### Part 2: Execution phase

#### Step 4: Generate the shot

**Global constraints** (important; all must be met):

* LT-1: One continuous long take — every action beat described by the user must fit within the same uninterrupted camera movement. Never insert cuts or split it into multiple storyboard shots.
* LT-2: The camera must move ahead of or in sync with the subject, with clear intention (pushing in, discovering, whipping, orbiting, rising, descending). The image must never feel neutral or uninvolved.
* LT-3: When moving between two subjects or characters, the camera must stay in the same continuous movement, never split into separate shots.
* LT-4: Connect every pair of beats with at least one phrase enforcing continuity without cuts, such as “immediately,” “without stopping,” or “within the same continuous movement.”
* LT-5: Open with a clear entry beat and end on an image that mirrors or echoes it, such as a matching close-up, a returning gesture, or stillness after movement.
* LT-6: Even the quietest beat must contain at least one subtle sign of camera life (gentle breathing movement, soft drift, or parallax). The entire video must not be completely static.
* LT-7: Do not generate BGM or a score; retain only ambient and natural sound. Add music in the editing stage only if the user explicitly chooses it later.
* LT-8: No screen text, overlays, subtitles, or watermarks.

Tool invocation rules:

* No subject reference and a generic appearance is acceptable → call `text2video` with the complete scene description.
* No subject reference but a specific appearance must be preserved → generate one reference frame with `text2image`, then call `image2video`.
* The user provides reference assets → animate a single image with `first_last_frame`, or use `m2v` for multimodal reference; choose by actual asset type and model capability, and reference assets with the main Skill's `--ref` and prompt placeholders.

#### Step 5: Quality check

Check the result against LT-1 through LT-8. If there are visible cuts, passive camera movement, an ending that does not echo the opening, or generated music, refine the prompt and regenerate within the existing authorization and credit limit, with at most three retries; beyond that, explain the plan and get approval first.

## Follow-up principles

* Use scenes, subjects, or camera viewpoints already provided by the user without asking again.
* Collect missing required information through a form, offering the scenario defaults above for one-click confirmation.
* The user may override viewpoint, aspect ratio, subject references, and other parameters at any time; adjust accordingly.

## Global constraints

1. Regardless of the number of action beats, the shot remains one continuous long take without cuts.
2. The camera always has a clear intention and acts as an active narrator, not a neutral observer.
3. Movement between two subjects must remain within the same continuous camera movement and must not be split.
4. Connect beats using explicit language that preserves continuity without cuts.
5. The opening and ending beats echo each other.
6. Include at least one subtle sign of camera life; never keep the entire shot completely static.
7. Do not generate music or a score. Unless the user chooses music in the editing stage, audio consists only of ambient and natural sound.
8. No screen text, overlays, or watermarks.
