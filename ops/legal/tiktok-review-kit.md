# TikTok review kit — what the app review asks for, ready before we apply

TikTok's Content Posting API review asks for two things a code repo cannot
generate on its own: a **privacy policy URL** and a **demo video** showing the
posting flow. Both are prepared here so the application is not returned for
paperwork. Nothing in this file is published by the app itself.

Status: draft. Blocked on one fact only — the contact address to publish.

## 1. Privacy policy (publish as a static page)

Hosting: a small public GitHub Pages site (`aeris-legal`), because the music
repo is private and Pages on a private repo needs a paid plan. Free, static,
one file.

```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Privacy Policy — AERIS Music Uploader</title></head>
<body>
<h1>Privacy Policy — AERIS Music Uploader</h1>
<p>Last updated: {{DATE}}</p>

<h2>Who this app is for</h2>
<p>AERIS Music Uploader is a single-user tool. It is operated by the owner of the
TikTok account it is authorized for, to publish that owner's own music videos.
It is not offered to the public and has no other users.</p>

<h2>What the app accesses</h2>
<ul>
  <li><strong>Login (user.info.basic)</strong>: the account's display name and
      open id, used only to confirm which account is authorized.</li>
  <li><strong>Content Posting (video.publish)</strong>: permission to upload a
      video file to that same account.</li>
</ul>

<h2>What the app stores</h2>
<p>OAuth access and refresh tokens, kept in an encrypted vault on the operator's
own machine. No analytics, no advertising identifiers, no third-party data, no
data about viewers.</p>

<h2>What the app does not do</h2>
<p>It does not read other users' data, does not post on behalf of anyone but the
authorizing account, does not sell or share data, and does not run advertising.</p>

<h2>Retention and deletion</h2>
<p>Tokens are deleted when the operator revokes access in TikTok
(Settings → Security → Manage app permissions) or removes them from the vault.
Revoking access ends all further use immediately.</p>

<h2>Contact</h2>
<p>{{CONTACT_EMAIL}}</p>
</body></html>
```

`{{DATE}}` and `{{CONTACT_EMAIL}}` are the only substitutions; the address must
be one K is willing to publish (a channel mailbox is enough — a personal inbox
is not required).

## 2. Demo video (30 s, screen recording)

The reviewer must see the whole path from "a video file exists" to "TikTok shows
the uploaded post". Record after the first successful sandbox post, in one take:

| time | on screen | what it proves |
|---|---|---|
| 0–4 s | terminal: `python3 ops/tiktok_auth.py --client-key … --redirect-uri …` printing the authorize URL | the app starts the OAuth flow itself |
| 4–10 s | browser: TikTok consent screen, scopes `user.info.basic` and `video.publish` visible, Approve tapped | the scopes match the policy above |
| 10–14 s | terminal: the exchange command completing, then `--check` printing `available: True` | token obtained and usable |
| 14–24 s | terminal: the publisher uploading one clip, progress output | the API is used for its declared purpose |
| 24–30 s | TikTok app: the uploaded post visible in the account | end result, same account, no other user |

Rules for the recording: real flow only, no edited success, no invented numbers,
and the video file shown must be the channel's own music clip.

## 3. What this changes about the plan

Until review passes, the app can post only to a private/test audience. So TikTok
stays a **pipeline test** in the near term and is not counted as a discovery
channel for this quarter's viewer target. The audit of 2026-11-26
(`ops/audits/yt-audit-2026-11-26.md`) shows the hours are already coming from the
long-form volumes, which do not depend on TikTok.
