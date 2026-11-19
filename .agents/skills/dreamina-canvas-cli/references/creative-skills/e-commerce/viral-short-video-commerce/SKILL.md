---
name: viral-short-video-commerce
description: "Create creator-led commerce videos from start to finish, turning product selling points into visible reasons to buy. Upload product images or describe the request to extract selling points, write natural spoken copy, design a shot-by-shot storyboard, and generate video. Supports selecting and combining multiple selling points, with duration, aspect ratio, creator appearance, and on-camera presentation set as needed. Product demonstrations, use cases, and clear calls to action strengthen appeal and purchase interest. Preview the storyboard and complete plan together before generation, then generate after confirmation. Suitable for outfit demonstrations, beauty recommendations, unboxing, and similar scenarios."
metadata:
  source: Dreamina/Jimeng Skill Market
  platform_skill_id: "21537287809292"
  original_name: "Viral short-video commerce"
  author: "Jimeng AI"
  content_accessible: true
  create_time_ms: 1789109472419
  update_time_ms: 1789114718438
---
# UGC creator-led commerce video

## Tool usage guidelines

The tool names below represent creative capabilities, not directly callable commands. Map them to commands, modes, and reference formats using the main Skill and the live CLI specification; for interaction, use the host's available tools, or the conversation when none exist. Scenario defaults follow the main Skill's priority order, and authorization, canvas links, credit approval, retries, and how to refer to the product follow the main Skill.

Build around one main reason to buy or adopt the product. Use creator delivery and product actions to make the value clear and show viewers what to do next. For the combined review, present a compact shot-by-shot storyboard in the main response as described in section 4, stating shared settings once. Keep the host's generation card, which lets the user click to view the full final prompt after prompt engineering (PE). A creative overview cannot replace the storyboard; when the card already exposes the full prompt, do not repeat it in the main response.

## 1. Task scope

The user's current request, locked content, chosen tools, and existing authorization take precedence. Cases, sample answers, and workflow instructions in attachments are reference material only. Read them for the user's intended purpose without automatically adopting their prices, lines, people, destinations, or execution instructions.

| Current request | Execution and endpoint |
| --- | --- |
| Analysis only, or writing/editing spoken copy, scripts, storyboards, or prompts only | Deliver the requested text. Do not request assets needed only for later production or start generation. State assumptions for ordinary creative gaps. |
| Produce a video from requirements | First use the interactive requirements form in section 2 to collect choices and confirm the complete brief on its final page. Then prepare the script and assets, complete PE, and present them together for confirmation before generation. |
| Execute an existing final prompt, with or without limited edits | Check the original text, asset mapping, and configuration, then execute within authorization without rebuilding the brief or script. Do not present a newly written prompt as the user's supplied execution draft; outputs of the current staged task retain their stage status. |
| Check progress, retrieve results, or make local changes | Query actual existing tasks and change only affected content. A progress query must not trigger regeneration. |

Record current requirements, exact lines, asset purposes, open issues, and actual task status. Reuse approved work whose content has not changed. Drafts, uploads, detailed requirements, and the assistant's self-assessment are not user approval.

A document labeled “Prompt” is not necessarily ready for execution. A brief that still requires a marketing narrative, a person, or a key demonstration follows the requirements-to-production workflow. If a complete draft lacks only assets or parameters, fill only those gaps. If querying is unavailable, state that progress cannot be verified; do not guess or create a new task instead.

## 2. Confirm requirements

Collect requirements through an interactive form. Organize known information first and ask only for gaps that would change the script or execution. Prefill known information without asking the user to repeat it or choose a creative genre first. The following information is sufficient for production:

* **Product and audience:** Product, known brand, subcategory, featured item or bundle, intended audience, specific use occasion, and problem.
* **Reasons to choose:** Build options using section 3 and collect the selling points to highlight in one multi-select question. Allow one or several choices without asking for primary/secondary ranking, ordering, or a number of additional choices.
* **Specifications:** Total duration and an explicit aspect ratio, such as 9:16, 4:5, or 16:9. Ask about platform only when it affects framing, destinations, or execution. Keep people, products, subtitles, and the CTA clear of interface overlays. When platform and placement are known, check current official safe-area and cropping rules; otherwise use conservative central framing without inventing pixel values.
* **People and sound:** Creator source, visible body range, on-camera speech / voiceover / no speech, and the user's specified voice direction.
* **Action and assets:** CTA goal, authentic destination and presentation method; existing product/person assets, verbatim locked content, and constraints.

For ordinary creator-led commerce, default to a visible creator speaking on camera. If the person's source is unknown, determine whether to use an existing person or generate a new one. For partial appearances, choose the visible body range based on product actions and honor stricter restrictions such as “hands only.” Strictly no people also excludes hands, bodies, silhouettes, human reflections, and people on screens. A video without people can still have voiceover; determine visible people and audio separately. Do not remove the creator or speech merely to simplify generation.

Separate facts from creative choices. Settings, pacing, performance, and camera movement can be designed reasonably. Do not invent exact prices, promotions, dates, specifications, ingredients, certifications, sales figures, numerical results, real identities, or purchase destinations. Recommended qualitative selling points must fit the known product; do not present them as measurements, long-term evidence, or guarantees that were not supplied. Appearance images cannot establish comfort, breathability, elasticity, wrinkle resistance, or long-term effects. Such directions require supporting information or explicit user input and cannot be entered directly as known facts. Choosing a creative direction does not supply product evidence. Without a CTA destination, do not claim a product card, bottom-left link, or other purchase location is available. Resolve information conflicts only where they affect the current delivery.

### Interactive requirements form

**Invoke first, then wait for choices.** On entering the requirements stage, check the forms, questionnaires, or clickable-option tools and parameters actually provided by the host. When available, invoke them; do not replace an interactive form with a Markdown table, numbered list, static card, or “let me know if you want changes.” Briefly explain what is being collected without filling out the entire brief on the user's behalf and asking for blanket approval. Use actual tool names, fields, and events; do not guess interfaces or claim displays or clicks that did not occur.

* **Prefill and state:** Mark known information as “provided” or “selected by the user,” assumptions and recommendations as “awaiting selection,” and missing facts as “information needed.” Only the first two belong in confirmed requirements. Do not automatically select recommendations. If the host has default focus or a preselection, wait for an actual user submission before recording the choice. Do not infer confirmed age, audience, featured product, duration, ratio, or person source from an image.
* **Questions and options:** Each question resolves one real decision. Ordinary single-choice questions offer two or three concrete options. Use only one selling-point question, “Which selling points would you like to highlight? (Select one or more),” offering four to six applicable options or fewer through the host's actual multi-select type or parameters. Allow one or several choices without a fixed maximum. Do not ask for a “primary selling point,” “secondary selling point,” or “how many extras.” A multi-select title over a single-choice control is insufficient. If multi-select is unsupported, state that and follow the missing-capability rule; do not split it into primary/secondary single-choice questions. Recommendations may be labeled but not preselected.
* **One custom-entry route:** Each question has at most one custom text entry. Check whether the host automatically supplies “Custom / Other.” If so, put only concrete actionable answers in the ordinary option array; do not add synonymous options such as “custom duration and ratio,” “other specifications,” or “enter your own,” or enable a second route manually. Otherwise, provide one custom option with text input through the actual interface. Ordinary specification options state a concrete duration and ratio; use “Enter your preferred duration and aspect ratio” as the sole custom-input prompt. Deduplicate by meaning before rendering, even when labels differ.
* **Multi-select records:** Retain the full selected set; adding, removing, or paging must not leave only the last choice. Custom text can coexist with ordinary selling points, but empty text is not a selection. Include all chosen selling points in the final brief without claiming the user ranked them.
* **Dependency order:** If several products appear and the featured scope is unknown, first choose the featured item, a confirmed-for-sale bundle, or styling content, then offer selling points for that scope. Ask about other missing specifications, creator source, audience and occasion, sound, and CTA goal/destination/presentation only as needed, without repeating a fixed questionnaire. Use necessary text input for missing facts rather than invented options.
* **Rounds and changes:** Use at most five decision pages per round, with the host's actual pagination or question batches. Preserve answers when moving between pages, and update only affected questions after an upstream change. Explicitly defer critical gaps that do not fit; do not show overall confirmation in that round. Complete selling-point selection inside this form, without a separate approval round for selling-point cards.
* **Final-page confirmation:** Once critical gaps are resolved, combine user choices and known information into a complete brief on the final form page, with “Confirm marketing requirements and proceed to script and asset preparation” and a way to edit. Update the full brief with changes and keep it visible before final submission. That submission also confirms requirements; then complete the script, assets, and PE continuously before combined review, without sending another brief for duplicate approval. If requirements were already complete, show the prefilled final form page directly rather than switching to a chat table.
* **Event interpretation:** Saving an answer, ordinary “Next,” or a tool result containing only option values does not confirm the final page. A generic “Continue” does not approve content that has not been shown. If collecting choices and final confirmation require separate tool calls, display the complete final page before obtaining confirmation; do not treat the first answers as approval. If the user proactively asks to accept all recommendations, update only recommendations already shown concretely and still proceed to the complete requirements confirmation page.
* **Missing capabilities:** If no form tool is available, or an invocation fails and cannot be recovered by retrying that capability, state that the interactive form is unavailable and pause requirements collection. Do not fake a form or silently substitute a completed brief. Use equivalent individual choices and final confirmation through text only when the user explicitly accepts text Q&A. Honor an explicit choice of another interaction method or a review waiver within its scope.

### Production stages and stopping points

When making a video from requirements, default to only two business approvals: requirements confirmation and combined approval of the script, assets, and final prompt. Collect choices through the form and use the complete brief for final-page confirmation. Then prepare the script, assets, and PE compilation/checks continuously and present everything in one review; do not add approval between script writing and PE. Before combined approval, do not start video generation or delegate generation to another executor. A native preview card awaiting user confirmation may be prepared under section 6.3. Text-only tasks end with the requested text; direct execution of an existing final prompt follows section 1.

| Stage | Required presentation | Next step allowed after user confirmation |
| --- | --- | --- |
| Requirements confirmation | Complete brief on the interactive form's final page: product and brand, audience and occasion, selected selling points and supporting details, duration, explicit ratio, person source and visible range, sound, CTA, asset purposes, and locked content. Resolve critical gaps before submitting this page for confirmation. | Write the script, prepare necessary assets within the agreed scope, complete PE compilation and checks, and assemble the combined review. |
| Combined script and final-prompt confirmation | Present the compact shot-by-shot storyboard and shared settings in the main response according to section 4. The eight information items may be combined, and shared settings inherited. Also provide all actual control assets and their purposes, a native card opening the full post-PE prompt, check rationale, and generation configuration. Explain the visual plan through the storyboard and existing assets. All information must agree; a promised upload or asset name does not mean the asset is ready. | One confirmation covers the current script, assets, final prompt, and configuration; then invoke video generation with that same content. |

Requirements confirmation is determined by the form's final-page event. If the user explicitly chooses text Q&A, use an explicit reply after showing the complete brief. Combined approval is an explicit reply or confirmation event agreeing to generate the complete reviewed plan; do not approve the storyboard and prompt separately. Advance when a tool has already returned valid confirmation, without also waiting for chat confirmation. Uploading images, detailed requirements, “creator-led commerce ad,” “make me a video,” “you decide the rest,” assistant self-assessment, and attachment examples do not replace these approvals.

**Scope of “continue”:** If the main response shows the full storyboard, actual assets and configuration are viewable, the card opens the full post-PE prompt, and it is clear that approval starts generation, “continue / confirm” or the corresponding generation button can serve as one combined approval. If only a creative overview is shown, the storyboard is missing, or the full prompt cannot be viewed, “continue” permits only completion of the review materials, not actual generation. Requirements inferred from images remain form options only.

Waive a stopping point only when the user explicitly waives that review or explicitly requests autonomous completion of the entire workflow without stage approvals, and only within that scope. When confirmed content changes, update the affected script, prompt, assets, and configuration together, recheck them, and show the relevant content once for approval instead of splitting it into multiple rounds.

**Before invoking generation:** Requirements approval is valid, the combined review materials are complete, PE has actually been checked, and the user approved the current combined plan; alternatively, an explicit review waiver covers the relevant review. Do not start video generation while required conditions are missing. Section 6.3 governs creating preview cards awaiting user confirmation; do not call an already started task a preview. Authorization to prepare references is not authorization to generate the final video.

**Native-card confirmation:** When the main storyboard, assets, and configuration are complete, the card exposes the full final prompt, and generation starts only after the user clicks, a native “Generate all” button can confirm both the combined plan and costs without additional chat confirmation. A dialog containing only price, thumbnails, or a summary cannot supply a missing storyboard, PE check, or full prompt.

## 3. Selling-point selection and product demonstration

### 3.1 Make the reason to buy clear first

A selling point answers “Why choose this?” and must express a result or feeling for the consumer. Identify the subcategory and featured scope first. With multiple products, distinguish a featured item, a confirmed-for-sale set, or the complete styling concept. An accessory appearing in an image does not establish that it is included in the sale.

| Content | Role | How to distinguish it |
| --- | --- | --- |
| Selling point | A reason to choose that the user wants the video to convey; several may be selected | Examples include “less effort coordinating everyday outfits” or “comfortable movement.” Each is an independent benefit, not just a setting or repeated synonyms. |
| Supporting detail | A fact, structure, or sensory detail making a benefit concrete | Visible colors, neckline, or actual compartments; explain how the detail supports the benefit. |
| Occasion | When the reason is useful | Leaving home in the morning or an office afternoon snack; the occasion itself does not prove a benefit. |
| Demonstration action | Makes a benefit visible or audible | Changing outfits, packing and retrieving, tapping and blending, or breaking food; an action alone is not a selling point. |

Even without the brand and product name, the copy should retain a specific reason to choose. “Show the front,” “see the structure,” “first decide whether it fits,” and “great quality” are insufficient. Write the consumer benefit first, then find supporting evidence. Do not replace an intended functional benefit with packaging or appearance just because those assets are easier to film.

### 3.2 Build options and allow multiple choices

1. **Organize evidence.** Separate user-provided information, visible facts, and creative directions awaiting confirmation. Visible color, silhouette, and texture can support styling ideas; appearance images cannot establish composition, comfort, fit range, internal structure, performance, or lasting effects. Non-visible qualitative experiences may be proposed for confirmation, while precise specifications and efficacy claims follow user or product information. Reuse supplied information without requesting it again.
2. **Offer distinct directions.** Choose four to six independent options that actually fit the subcategory from task outcomes, sensory appearance, comfort and fit, sustained performance, operating efficiency, portability, and style expression. Do not pad the list if only two or three apply. Do not bundle “high coverage / natural lightweight finish,” “lasting / comfortable,” or “space-saving / fast processing,” or repeat one reason through synonyms.
3. **Put options in the multi-select form.** Invoke the interaction tool as described in section 2. Each option shows “specific benefit title | who or when it helps | current evidence or open question | how to demonstrate it.” Avoid bare labels such as “premium, versatile, slimming”; static cards are not clickable options. One sentence is enough for the demonstration idea. Do not develop full spoken copy or a storyboard before requirements are confirmed. When recommending an option, explain its fit with the product, purchase motivation, demonstrability, and duration.
4. **Let the user select several.** Ask one question: “Which selling points would you like to highlight? (Select one or more).” Allow one or several choices and additions through the question's single custom entry. Do not require the most important choice first or ask for priority, ranking, or a number of extras. One selection is sufficient to continue. Record all choices as one selected set; a recommendation does not automatically become a user choice.
5. **Bind choices to this video.** Specify “selected benefits / supporting details for each / demonstrations / completed results” and confirm them with the complete brief. Unselected options do not enter the script. This belongs to requirements confirmation in section 2, adding no separate approval round and not replacing the later combined script/prompt approval. After confirmation, turn facts and details into natural language; choosing a direction does not lock the option card's wording verbatim.

### 3.3 Subcategory option library

Each semicolon-separated item is independently selectable. Filter by product facts rather than assuming all are true. Show only applicable options. For trying on, sensations, operation, and sustained effects, distinguish creative illustration from actual measurement.

| Subcategory | Independently selectable consumer benefits | Demonstration methods and conditions |
| --- | --- | --- |
| Tops / knitwear | A neckline sharpens the look; shoulder lines create a relaxed silhouette; length helps balance upper/lower proportions; color matches existing bottoms; knitted texture adds visual layers; room to move when raising arms | Neckline/shoulder close-ups, front/side views, tucking, changing bottoms, and raising arms. A flat lay cannot establish feel, elasticity, or pilling resistance. |
| Trousers / skirts | Waistline supports the intended proportions; legs/hem create the chosen silhouette; length complements shoes; shape changes with movement; comfortable sitting and standing; convenient pocket access | Front/side views from the same camera position, walking, sitting, changing shoes, packing and retrieving. Actual size, fit, and effects such as straighter-looking legs require information; do not manufacture them through lens distortion. |
| Complete outfits | A complete color scheme; coordinated upper/lower silhouettes; wearing pieces separately adds choices; switching shoes/bags moves between workday and weekend styles; one fewer color decision | Separate pieces to full outfit, separate wear, or changing shoes/bags while clothes stay fixed. Call it a set or promise included accessories only when sale information confirms it. |
| Shoes | Shape complements the target clothing style; colors coordinate with the outfit; fewer steps to put on/take off; natural foot flexion; comfortable walking for the intended period | Trousers and shoes together, continuous putting on/taking off, stepping and flexing. Cushioning, slip resistance, no rubbing, and long-wear comfort need evidence; walking footage is not verification. |
| Bags | Shape completes the look; color adds an accent; everyday items have clear compartments; phone access without rummaging; carrying styles fit different occasions; carrying comfort meets needs | Wearing, packing the same items, opening and retrieving, adjusting straps. Compartments, capacity, carrying styles, and loading conditions follow actual structure. |
| Hair accessories / jewelry | Color brightens a plain outfit; shape expresses personal style; changing accessories changes a hairstyle's mood; fewer steps to control flyaways; size fits the wearing area; supported hold or wearing experience | Putting on from the same camera position, opening and positioning, finishing the hairstyle, slight head turns. Several styles together do not imply a bundle; do not infer secure hold for every hair volume. |
| Concealer / base makeup | Local correction of dark circles or blemishes; higher coverage; natural lightweight finish; shade blending; supple fit under the eyes; easy blending with a small amount; even makeup for a chosen period | Identify the target area, then dab, layer, show edges close up, or record stages. Select coverage, natural finish, skin feel, and wear separately rather than combining them into an all-purpose base-makeup claim. |
| Lipstick / lip gloss | Color brightens the complexion; sheer application suits daily wear; layering increases presence; matte/glossy finish matches preferences; application is easy to control; color lasts for a selected period | Continuous sheer application and layering in the same light, light on lips, lip-edge close-ups. Exact shades follow supplied information; package color is not lip color. |
| Skin / body care | Preferred light or rich texture; smooth spreading; specified moisturizing/soothing goals; controlled dispensing; fits daily steps; convenient portable use | Drops, spreading, actual dispensing, and care steps. Care goals need evidence; glow or droplets do not prove fast absorption, repair, or wrinkle reduction. |
| Hair care / fragrance | Easier combing; desired volume or smooth styling; convenient routine; fragrance notes suit preferences; ritual fits the occasion; scent experience over a selected period | Combing to a finished style, actual use, settings matching supplied notes. Preserve hair type, amount, and tool conditions; do not invent scent longevity. |
| Crunchy snacks / pastries | Crisp bite; dense/soft texture; chosen flavor layers; a snack-sized portion; individual packaging for sharing; ready to eat or requiring few steps | Choose breaking/cutting/scooping/biting and synchronized sound for the actual food, with authentic portions. Do not combine crisp, molten, and dense characteristics without evidence. |
| Water / drinks | Pleasant drinking experience; complements food without overpowering it; distinctive flavor is memorable; carbonation or temperature sensation; easy grip and opening; size suits carrying | Pouring and drinking, opening sounds, placing in a bag at consistent scale. Carbonation, ingredients, water source, sugar-free status, calories, and functions must match the product; bottle footage alone does not explain why to drink it. |
| Portable blenders | Make a personal serving; turn prepared ingredients into a drink; transparent cup shows contents; fits a small counter; easy to carry; easy cleanup | For preparation, show ingredients → safe operation → finished drink; for portability, show packing, retrieving, and carrying. Do not invent capacity, ice crushing, smoothness, leak resistance, battery life, or removable washable parts. |
| Cleaning / kitchen appliances | Complete a specific task; fewer operating steps; batch size fits needs; reach narrow areas; compact storage; convenient maintenance; less impact on surroundings during use | Show inputs/outputs, continuous steps, scale, disassembly/cleaning, or real sound according to the chosen benefit. Time, capacity, noise, and energy use follow supplied conditions. |
| Phones / headphones and other electronics | Less waiting for common tasks; audio/video suits the use case; easy handoff between devices; lightweight carrying/storage; suitable wearing fit; battery life reduces charging interruptions; top up during short breaks | Actual interaction feedback, sample footage/recordings, connection tasks, storage, and battery readings at stages. Appearance cannot establish AI features, compatibility, speed, battery life, or protection. |
| Home / storage | Items have their own places; less searching when retrieving; dimensions fit a corner; combinations change the use; support or feel suits daily life; easy cleaning/care | Pack and retrieve the same items, show true scale, combinations, sitting/leaning, or cleaning. Keep materials, capacity, stability, and included accessories consistent. |
| Apps / services | Fewer task steps; guidance for first use; faster filtering; shared information stays synchronized; personal customization; clear support when problems arise | Same-account task → key operation → completion; show actually available interfaces and services. Time savings, privacy capabilities, and paid benefits need corresponding information. |
| Cars / mobility | Load space fits needs; easy layout changes; convenient refueling/charging plans; ride experience suits the occasion; parking or terrain capability; predictable vehicle services | Loading, layouts, operations, and routes for the same model/configuration. Range, driving assistance, safety capabilities, and costs follow supplied limits; keep operation safe. |
| Sports / outdoors | Light carrying load; fit adjustment suits movement; quick setup/access; grip suits terrain; temperature/moisture management matches conditions; supported protection | Wearing/adjusting, continuous actions, setup and packing. Keep terrain, participant ability, and equipment consistent; do not invent waterproofing, sun protection, or safety certifications. |
| Pets | Food suits life stage; eating experience; convenient grooming; easy cleaning or odor management; enriching play; suitable resting space; appropriate travel restraint | Feeding, grooming, litter-clump cleaning, play, entering/leaving bedding, and restraint. Keep species, size, amount, and supervision consistent; behavior does not prove health improvement. |
| Baby care | Size suits the age stage; clear feeding preparation; fewer care steps; fit or absorption performance; convenient travel storage; easy interactive play | Preparation, dressing, packing/retrieving, and interaction with adult care. Age, materials, safety, amount, and use posture follow actual requirements. |
| Health products | Easy daily adherence; clear amount/dosage; accessible records; comfortable support and fit; relaxation routine suits the occasion; defined professional support | Operation, recording, wearing, or daily routines. Distinguish experience from medical conclusions; do not add efficacy, measurement accuracy, or suitability guarantees. |
| Education / knowledge | Clear learning path; feedback after practice; representative content is understandable; flexible scheduling; projects relate to use; clear question support | Same-task learning → practice → feedback → correction, showing real content samples. Do not invent instructor qualifications, scores, or guaranteed learning results. |
| Travel / accommodation | Convenient arrival; room space suits needs; appropriate itinerary pace; distinctive food; clear package inclusions; defined reception and rescheduling services | Arrival, stay, activities, and service touchpoints for the same location/room type/dates. Do not invent facilities, availability, distances, or price conditions. |

For unlisted categories, derive options through “specific problem → product action/attribute → everyday benefit.” Prices, promotions, certifications, sales, and reputation can be reasons to buy, but use only the precise information currently supplied; do not automatically add low-price comparisons, time limits, or scarcity.

### 3.4 When there is only one outfit flat-lay image

For example, an image shows only a gray knitted top, white trousers, a bag, and shoes, with no person or label. First ask whether the focus is the top, trousers, or styling content. Within that scope, offer distinct directions such as:

| Option | Consumer benefit | Possible demonstration |
| --- | --- | --- |
| Fresh gray-and-white colors | A clear color idea for a light-toned outfit | Move from color details to the full outfit, preserving actual colors. |
| Simple colors with visible detail | Visual layers in a basic outfit | Move from visible knitted texture to the full look. |
| Less effort getting dressed in the morning | Follow this outfit idea when preparing to go out | Move from separate pieces to the full outfit; do not claim the products are sold together. |

These remain options, not locked script claims. Put them in the interactive question “Which selling points would you like to highlight? (Select one or more).” Do not infer unspecified brands, slimming/straighter-leg effects, non-itching fabric, or pilling resistance from a flat lay. Do not pad the list with three synonymous versions of “versatile.”

### 3.5 From selected selling points to actions and spoken copy

For video production, do this after requirements confirmation. For copy or script-only requests, write directly within the user's scope without extra production approval. Organize “consumer situation → specific benefit → supporting fact → product action → completed result.” Sound adds the benefit; visuals perform the demonstration. The following mappings are examples only and must fit the current product and selected directions:

| Selected selling point | Visual payoff | Spoken-copy direction |
| --- | --- | --- |
| Convenient commuting | Pack, retrieve, and carry at realistic scale | “It goes in my work bag, so there's one less thing to carry.” Do not add leak-resistance or long-battery-life claims. |
| Concealing dark circles + natural finish (both selected) | Dab and blend the relevant area, ending with the concealed area naturally merging into surrounding skin | “Even this bit under my eyes, blend the edges, and it still looks natural.” Preserve skin texture without claiming a real test. |
| Crunchy snack | Break and bite with synchronized cracking sound; allow time for the bite | “When I want something crunchy in the afternoon, this bite hits the spot.” Do not say “demonstrate the crunchy selling point.” |
| Easy-to-find storage | Sort the same items into places, then retrieve needed items continuously | “Cables here, little things there—less rummaging next time.” Do not merely repeat “now put it in.” |

Each selected selling point must have a specific action, detail, or experience carrying it. Do not split the same fact into several synonymous lines. During scripting, arrange order, emphasis, and rhythm for the duration so the benefits form a clear narrative, without asking the user to rank them again. Reserve time for the payoff and CTA. If the natural time window cannot hold all selected content, explain adjustments in script review instead of silently deleting choices.

### 3.6 Creative structure and payoff

Choose actions that deliver the selected benefits, then choose direct-to-camera delivery, a response to a problem, demonstration, tutorial, unboxing, or everyday use. Add comparisons, promotions, or a small story as needed. A problem response can use a neutral question, but must not invent real commenters or endorsements.

The narrative is “product-related hook → early product and main value → action/experience as evidence → payoff → known brand or product close → one CTA (omit only when explicitly unwanted).” Open with a specific problem, wish, action, result, or detail. Usually establish the product connection within about the first 3 seconds, adjusted for duration, and fulfill every opening promise.

For visible changes, use “unresolved state → product intervention → completed change → result → action.” Keep the same subject, camera position, crop, lighting, and exposure in comparisons. The change should remain visible with sound muted and subtitles removed; hold the result long enough to see. Do not present an already beautified state as the before state or manufacture evidence by changing subjects, lighting, or smiles. Without visible change, show an actual process, completed task, or supported sensory experience.

Synthetic demonstrations may present user-selected qualitative makeup or experience directions that fit the product, but must not pretend to be real tests, real testimonials, or verified efficacy. Even without a test, retain an appropriate completed result without adding numbers or guarantees. If a story is needed, one conflict and one product-driven resolution are usually enough; setup must not crowd out the demonstration.

## 4. Spoken copy and storyboard

First establish “who speaks to whom, at what moment, about which problem, with which product facts/actions, how daily life improves, and which words must be exact,” then write the connected full text. Do not start with a shot table and force one line into each shot.

Use everyday verbs, concrete sensations, and natural pauses, developing one idea at a time. Images handle actions; speech adds context, benefits, explanations, judgments, decisions, or the next step. If it adds nothing, leave space for product or ambient sound. Do not have the person speak production instructions, shot plans, or backstage phrases such as “build trust” or “prove the selling point.”

For example, replace “show the indicator light's completion feedback” with “Come back when the light's on—you don't have to stand over it.” This illustrates wording, not evidence that the current product has an indicator light. Creators may express supported immediate feelings and preferences. Synthetic people must not impersonate named real people, experts, or real customer testimonials, or invent purchases, long-term use records, or measurements.

After writing the full text, check every sentence:

1. **Meaning:** Do the product, action, references, and sensations match current facts?
2. **Natural speech:** Would this person say this to the listener in that setting? Does it sound like a voice message?
3. **Contribution:** What does it add beyond the images and previous lines? Does it express a specific reason to choose?

When the brand is known and speech is included, say it naturally and accurately at least once in the actual dialogue. A title, logo, packaging, or subtitle does not replace this. Without speech, plan a specifically readable brand presentation. Do not guess unknown brands. Preserve locked lines verbatim and use the specified pronunciation for brands and easily misread words.

**Define three CTA elements separately:** What viewers should do, what they act on or where they do it, and whether speech, visuals, or the platform carries it. If the purchase goal is clear but its destination is missing, fill only that gap rather than changing it into generic usage advice. Without a purchase goal or destination, choose an appropriate product-adoption action for the scene; do not invent product cards, links, or search terms.

First deliver the payoff and echo the opening, then give a specific action and object. “I'd buy it again,” “take a look,” and “brand + try it” cannot independently serve as the CTA. With an authentic product card, for example, say “Open the product card and choose this true red.” Without a destination and with everyday adoption as the goal, say “Before heading out in the morning, use this under your eyes.” The line must match the video's facts and preceding content; choosing a direction does not lock sample wording verbatim. When the user explicitly wants no CTA, include no audience-directed buying, clicking, selecting, or usage instructions anywhere. The person may describe their own actions and experience, closing on the result and known brand/product.

After self-checking, divide lines by natural pauses and product actions. Estimate each line's time window, allowing pauses, expressions, synchronized actions, product sound, and the final frame. Total word count cannot replace line-by-line timing. If a section runs long, remove filler, merge repetitions, or reduce secondary content rather than rushing delivery. Estimates are not actual audio duration; use a read-through or TTS for calibration only when timing is tight.

**Storyboard presentation:** In the combined review's main response, use the title “Storyboard | Total duration · Aspect ratio” and show every shot directly. Default to compact ordinary Markdown text blocks, without tables, code blocks, HTML, collapsed sections, or cards with large blank spaces. Honor another explicitly requested format or a spoken-copy-only request. Open with at most one necessary explanatory sentence rather than repeating the brief, selling points, or lengthy “the plan is ready” preambles.

* **State shared settings once.** Before the shots, use one or two sentences for the common setting and lighting, BGM direction and relationship to speech, and shared sound effects. Shots inherit stated settings; note changes only where they occur. Unwritten settings do not count as explained.
* **One short title and three body items per shot.** Combine shot number and start/end times in the title. Use three consecutive list items, “Visual / Dialogue / Camera,” without blank lines between them. In one or two connected sentences, the visual describes the subject's initial state, action, and visible completed result rather than mechanically splitting four labels. Dialogue preserves the speaker and exact text; write “None” for no speech. Camera combines shot size, movement, local sound effects, and lighting changes with semicolons. A fixed camera can simply say “Fixed”; moving shots retain the path from starting to final framing.
* **Keep all eight information items, allowing combination and inheritance.** Shot number, duration, image, shot size, lighting, dialogue/voiceover, sound effects, and camera movement must be identifiable. Eight columns, eight lines, or repeated shared settings are not required. Put common information in the overall settings and differences in the relevant shot. Do not remove exact lines, concrete actions, results, or necessary continuity for layout reasons.
* **Wrap naturally.** The three items are information groups, not fixed screen-line counts. Let long content wrap within its container, preserving complete sentences as needed without truncation, shrinking text, or ellipses. Use normal paragraph spacing between shots without rules, oversized headings, or blank placeholders. Show the actual number of shots rather than merging them to fit a layout.

Layout example; replace every placeholder. Render actual delivery as Markdown, not inside a code block:

```markdown
**Storyboard | {Total duration} · {Aspect ratio}**

Overall: {Setting and lighting}; BGM: {Direction and relationship to speech}; shared sound effects: {Settings; note changes per shot}.

**01 | {Start–end time}**

- **Visual:** {Subject's initial state → main action → visible result, in connected short sentences}
- **Dialogue:** {Speaker}: “{Exact full text}”
- **Camera:** {Shot size}; {Fixed or movement from starting to final framing}; {Local sound/lighting differences; omit if unchanged}

**02 | {Start–end time}**

- **Visual:** {Inherited state, action, and result}
- **Dialogue:** {Speaker}: “{Exact full text}”
- **Camera:** {Shot size}; {Movement and necessary local differences}
```

Continue this structure for all shots. The actual storyboard must appear in the user-visible main response; a creative overview, selling-point summary, or “the storyboard is aligned” cannot replace it.

Give each shot one main event, one main camera movement, and at most two product details or outcomes to highlight. Express important emotions through eyes, mouth, breathing, shoulders, or hand behavior. Cut after the action finishes or explicitly continue it in the next shot. Hold the product and delivered result in the final frame.

## 5. Reference assets

First check whether existing assets support the actual shots: clear identity, visible key structure, and acceptable occlusion/cropping. Ordinary handling, opening/closing, or changing angles does not automatically require extra images. Fill only a necessary missing detail. Generated supplements are depictions, not independent evidence of product facts.

* **Product and person roles:** Product images control shape, color, material, packaging, and similar features; person images control appearance, hair, and clothing. When a new consistent creator needs a reference, first prepare a separate person image without the current product. Put holding, wearing, and application relationships into the video's actions.
* **Partial people:** For anonymous hands and similar appearances, default to shared text controlling visible body range, side, cuffs, contact, and continuity. Do not generate identity images merely because they recur; use images only for a necessary specific appearance or at the user's request.
* **Combined references:** Use only when the actual tool cannot reliably bind subjects separately or key contact geometry needs control. They cannot replace the product's identity source or justify unseen structure.
* **Use boundaries:** Identity/style references do not automatically become overlays, backgrounds, freeze frames, first/last frames, or closing product photographs. Direct inclusion of an original image must follow the user's specified use; review-only previews are not automatically generation inputs.
* **Actual mapping:** List “asset → subject → controlled content → allowed use → actual input handle.” Several views may still refer to the same product; state how many subjects appear in the result. Reference only real assets without inventing paths or handles.

During combined script/final-prompt review, show the actual necessary references and their uses. If a promised upload has not arrived, a draft is allowed, but do not call assets ready. If generation capability is missing, deliver what can be completed and state the gap without claiming nonexistent generated images.

When exact UI, prices, subtitles, logos, or CTAs cannot be produced reliably by the video model, use authentic assets or controlled post-production layers and reserve space and screen time. If those capabilities are absent, identify the unfinished work rather than promising the model will render text correctly.

## 6. PE and final video generation

For a video made from requirements, follow “requirements confirmation → script and asset preparation → PE compilation and checking → combined script/final-prompt presentation → one confirmation → generation.” Based on confirmed requirements, PE turns the same review-ready storyboard, lines, actual assets, and configuration into executable model instructions and checks completeness. The script need not be approved separately first. Fix script and prompt together before combined review while preserving locked content. The current Agent actually writes and self-checks them; use dedicated host PE capabilities if available, without inventing separate tools or review results.

An explicit review waiver removes only that stopping point, not the actual compilation and checks. Direct execution of an existing final prompt under section 1 checks text, inputs, and capabilities within its existing scope without rebuilding the storyboard or requesting extra stage approvals. Prompts newly written in the current staged task do not qualify for that entry path.

### 6.1 Write the complete prompt

Check models, duration, ratio, resolution, reference types/counts, segmentation, speech/lip-sync, and text capabilities against the actual definitions of currently available tools. Do not hard-code one version's specifications or guess commands or parameters. Honor the user's chosen tool. When Jimeng/Dreamina CLI is explicitly specified, use the official `dreamina-canvas` rather than switching generation services yourself.

The prompt and the script being reviewed must contain the same shot order, timing, actions, verbatim lines, brand, CTA, visible people, and asset responsibilities. Fix unlocked script and prompt content together when PE reveals issues, then review them together. Handle material changes to confirmed requirements or locked content within the affected scope. Use Chinese prompt text for Chinese requests, preserving exact names, units, and tool handles.

Use the following structure, omitting inapplicable items and replacing placeholders with this video's concrete content. Limited execution of an existing final prompt preserves its organization.

```text
Duration: … seconds; aspect ratio: …
Task: A creator-led commerce video in … language; … product solves … problem through … action/experience, showing … result.
Overall direction: Setting, authentic UGC feel, lighting and color, materials, pacing, and stable attributes.
Subjects and assets: Actual handle → subject and control role; subject count, visible body range, product ownership, orientation, and fixed relationships.
Sound: Creator speech/voiceover strategy; on-location and ambient sound; BGM direction and how it leaves room for speech.

Stage 1 | 0–… seconds | Purpose of this segment
Uses: Subjects and asset handles actually appearing here.
Image and action: Position, orientation, contact; starts with …, through … action/path/speed, visible … feedback, ends with ….
Camera: Shot size, subject anchor, starting composition → one movement path/fixed relationship → final framing and focus.
Product focus: At most two specific details or results.
Dialogue: Speaker: “Exact lines”; state explicitly if there is no speech.
Sound: Synchronized on-location/ambient sound; BGM continues, lowers, changes, or resolves.
Transition: State inherited by the next segment, or an explicit transition.

Continue through all stages. In the last stage, specify the sole final image, its hold, and how the selected CTA is carried.
Overall continuity: Stable product, person, setting, lighting/color, and sound attributes, consistent with the last stage.
```

Accumulate shot start/end times according to the script, continuously covering 0 through the total duration without redistributing evenly, overlapping, or leaving gaps. For example, shot lengths of 2.5, 4, 3.5, and 5 seconds become 0–2.5, 2.5–6.5, 6.5–10, and 10–15 seconds. For segmented generation, each segment starts at 0; explain segment order and joining continuity.

State spatial conditions and completed actions in each segment: grip/contact points, product orientation, necessary label details, and occlusion. One segment's completed state is the next segment's starting state. Changes of hand, position, ownership, screen direction, or camera axis need continuity. The last segment exclusively defines the final image; the overall summary must not add another ending action.

Use the current tool’s supported asset handles and upload order for image, video, and audio references. Define roles once globally and activate only the assets used in each segment. Keep only visual, sound, and asset-control requirements in the prompt; task-management information belongs in execution records.

### 6.2 PE checks

Before combined review, compare the **actual complete prompt** segment by segment against the same review-ready script, confirmed requirements, actual assets, and configuration. Check the following, resolve issues in script and prompt together, and then present them together. Do not mark “passed” first and use that label instead of checking.

| Check | What to verify |
| --- | --- |
| Timing and lines | Numeric start/end times match the storyboard and cover the duration continuously; lines, speakers, brand, and CTA are accurate, with enough time for natural speech and actions. |
| Actions and camera | Each segment has an initial state, main action, visible feedback, and completed state; movement has starting and ending framing; person positions, object ownership, orientation, and action continuity agree across segments. |
| Assets and capabilities | Every handle maps to an actual input and allowed use; subject count and visible body range are correct; generation configuration, assets, and audio approach fit current tool capabilities. |
| Marketing and ending | Selected selling points and demonstrated results remain present; the hook pays off; the selected CTA is carried correctly; the final segment's image matches overall continuity. |

For overload, remove repetition and decoration first without silently sacrificing evidence, exact lines, or the CTA. If a fix materially changes confirmed content, handle the affected scope and recheck. Unresolved issues cannot be marked as passed. Retain the actual objects checked, key reasoning, and unresolved items. Call a self-check a self-check; generating a hash, completing a template, or saying “everything aligns” does not prove PE was performed.

### 6.3 Present the storyboard and prompt card together

After PE, retain the host's native final-prompt card and click-to-view behavior. Do not rewrite the full prompt in the card or duplicate it in the main response. Present the combined review as follows:

1. **Main response: compact shot-by-shot storyboard.** Show all shots as described in section 4. Combine the eight information items as appropriate, stating shared lighting, BGM, and sound effects once. The storyboard is the main content, not a few creative beats or “the plan is ready,” and must not exist only in internal drafts, tool arguments, or collapsed execution records. If a post-tool final response replaces previous content, it must retain the full storyboard block rather than a summary.
2. **Native card: final video prompt.** If clicking the card reveals the full post-PE prompt that will actually be executed, the full-text visibility requirement is met. The card's outer face may be a summary and need not be expanded by default; the user can open it before confirming, without extra “have you read it?” approval. Use the main response or full text on the same page as a substitute only when the full prompt cannot be viewed.
3. **Actual assets and configuration.** Show assets or make them directly viewable, explaining subjects, roles, and uses. Use verified values for model, duration, ratio, resolution, segmentation, audio, and other configuration. Do not repeat information already clear in the card.
4. **PE check explanation.** Briefly describe the timing, lines, actions, asset mapping, and necessary limitations actually checked. Do not call self-checks independent review or substitute “everything aligns” for the checks.

**Order of cards and generation:** A host capability may be used during combined review if it only creates an item awaiting approval, clicking the card shows the prompt, and generation and its costs do not begin until the user clicks Generate. The full storyboard must also appear in the user-visible main response. Determine preview versus generation from actual tool behavior, not its name. Calls that immediately start generation still require combined approval first.

Once the full storyboard and clickable prompt card are ready, say “The storyboard is above. Click the card to view the final prompt; generation will start after confirmation.” Prefer the host's native generation button as one combined approval covering that script, assets, prompt, configuration, and displayed cost. Do not demand chat approval first and then duplicate card approval. If no native confirmation can carry the complete review, use one explicit reply or confirmation event. Follow the scope of an existing explicit review waiver without asking again.

Before presenting, check the actual user-visible content: all shots and time coverage are complete; the eight information items can be found in shots and explicitly stated shared settings; layout is compact and wraps naturally as in section 4; the full prompt is viewable in the card; and both use the same lines and timing. If the storyboard is missing, add it to the main response rather than rewriting or duplicating the prompt as a substitute.

### 6.4 Submit and query

Before invoking a production task, recheck that requirements are confirmed, PE was actually completed, the full storyboard and full-text prompt card received combined approval for the current plan (or an explicit waiver exists), and inputs and configuration have not changed. **The complete prompt reviewed together is the tool input.** Do not substitute a summary, storyboard table, filename, or “generate from the above,” or rewrite it just before submission. If only requirements were completed or only the storyboard was shown, complete sections 6.1–6.3 and obtain combined approval first. Once the full plan is confirmed, generate directly without another review. Direct execution of an existing final prompt relies on the user's instruction to execute that draft and actual input checks, without rebuilding this workflow.

Invoke only after confirming that actual authorization covers current content, asset purposes, configuration, and quantity. Save actual task IDs, inputs, and returned status. On timeout, query the original task first to avoid duplicate submissions. Respect existing limits on retry count, cost, and scope. If unclear and new costs would arise, explain the specific retry plan first; do not retry indefinitely or automatically switch services.

## 7. Quality checks and delivery

| Area | Actual checks |
| --- | --- |
| Content | Selected selling points are presented and form a clear narrative; the hook pays off in the middle; result and selected CTA connect. If the user explicitly requests no CTA, omit action instructions throughout. Do not invent facts, and ensure a known brand actually appears. |
| Speech | Read the full text; meaning is sound, delivery natural, and every line adds information. Exact text fits each time window. |
| Visuals | Product and person identity stay consistent, contact is credible, actions can be completed, comparison conditions match, and the final frame is clear. |
| Execution | Required assets exist, purposes and handles are correct, configuration fits current capabilities, and the full prompt matches the actual input. |
| Final output | Watch and listen to the actual result. Check file usability, black/frozen frames, required audio, missing lines, garbled text, identity drift, key evidence, and the CTA. |

Fix affected content when checks reveal an issue, then recheck affected parts. Changed lines require retiming that segment and updating its prompt; changed product/person identity requires rechecking related shots and assets. For batches, preserve the correspondence of facts, lines, assets, and configuration for each item; one passing item does not validate the whole batch.

Give conclusions only after checking actual content item by item. Call self-checks self-checks, and only actual independent review independent review; do not claim checks that were not performed. Deliver only the current correct outputs, usable files/links, and necessary limitations. State accurately when generation has not happened, is still queued, or post-production remains undone.
