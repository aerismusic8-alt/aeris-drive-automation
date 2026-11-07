# Avatar: one tap for K (the only step that cannot be automated)

The banner is already live — it went up through the YouTube Data API, no human
needed (`ops/apply_channel_art.py`). The **avatar** is the one piece YouTube gives
no API for, so it needs a signed-in Studio session. This pod has no YouTube
session (the login vault snapshot holds Facebook, TikTok, Flow Music and Google
*web* cookies, but no `youtube.com` session), so it is a one-minute job for K.

The artwork is done and committed: `channel/avatar-pro-800x800.png`.

## Do this once

1. Open the cloud desktop and sign in to Google as **aerismusic8@gmail.com**
   (the agent never sees the password):

   `https://work-1-binldertyzenrvzu.prod-runtime.all-hands.dev/vnc.html?autoconnect=1&resize=remote`

2. In that browser, go to **YouTube Studio → Customisation → Branding**
   (`https://studio.youtube.com/channel/UCm44BjAn03ruOF-WaA3ZRww/editing/images`).

3. Hover the profile picture → the camera/pencil button → **Change** →
   **Upload** → pick
   `music938-1/channel/avatar-pro-800x800.png` → **Done** → **Publish**.

Then tell the agent "อวตารเสร็จแล้ว" and it will run
`python3 ops/login_vault.py save`, so this sign-in survives the next pod and the
avatar never has to be done by hand again.

## Why not fully automatic

`channelBanners.insert` + `channels.update` exist, so the banner is scriptable.
There is no `channelAvatars.insert` — YouTube has never exposed an avatar write.
The alternative would be holding K's Google password, which the standing rules
forbid. So: banner = automatic, avatar = one tap.

`ops/set_avatar_studio.py` is written and ready to do steps 2–3 unattended
(hover → upload → publish, with screenshots at every step). It only needs a
signed-in desktop; run it right after the sign-in above and it will finish the
job without the manual clicks.
