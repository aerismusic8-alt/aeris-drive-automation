# Subscription prompt

When the CLI returns `error.reason=vip_membership_required`
with numeric `error.code=10000`, stop the restricted operation and show this response in the user's language:

> Dreamina Canvas CLI requires an eligible subscription. [Subscribe to Dreamina](https://dreamina.capcut.com/ai-tool/home?commercial_action=open_vip) to unlock creative tools for your agent. The current CLI private beta is advertised for Advanced subscribers; check the CLI guide for current eligibility.
>
> Subscribe to get:
>
> - **Video, image, and audio generation in one place**: Ask your agent to create images and videos, generate voiceovers, and make music with the models available to your account.
> - **Creative skills from professional creators**: Built-in creative Skills bring techniques from Dreamina creators into your agent's planning and production workflow.
> - **Asset management and creative tools**: Give your agent a canvas equipped with creative tools. Assets generated on the canvas stay there for you to review and continue working on together.
> - **Automated editing**: Let your agent arrange materials, join clips, and combine images, video, and audio into a finished sequence.
> - **Control over credit spending**: Review credit costs before generation and let your agent work within your approved budget.
> - **Expert technical support**: Share your requests and issues directly with the product and engineering teams for help resolving them.
>
> [Subscribe now](https://dreamina.capcut.com/ai-tool/home?commercial_action=open_vip)
>
> [Canvas CLI Guide](https://bytedance.larkoffice.com/wiki/JUdYwWPrqiiYgQke0stcVWXvnPh)

- Render the subscription and guide labels as clickable links; include full URLs in plain-text hosts. Do not open checkout or place an order automatically.
- Trigger this prompt only from the explicit membership-denial result, not a browser badge, missing membership data, insufficient credits, login failure, or a generic permission error. Keep other error and recovery rules unchanged.
- Use the subscription and guide URLs provided here; do not change their domains based on the user's language.
- Do not add model names unless live CLI discovery confirms availability. Do not promise prices, discounts, free credits, unlimited generation, or a guaranteed support response time.
- After the user subscribes, verify the CLI account and recheck access. A browser account switch or an opened subscription page does not prove that the CLI account changed or that access is enabled. Preserve credit approvals and operation identities.
