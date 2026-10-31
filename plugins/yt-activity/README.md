# yt-activity

An OpenHands automation plugin (script runner, no LLM) that checks every AX
YouTube channel once an hour and records subs, videos, views and the age of the
newest upload. A channel that has not uploaded within `stale_hours` is flagged
`STALE`.

The reading is written to the automation KV store, so it survives the sandbox:
`latest` holds the newest row per channel, `history` the last 96 rows. A channel
whose refresh token is missing or rejected records `auth_error` and the run still
succeeds, so a broken credential is a visible gap rather than a silent absence.

The refresh tokens are OpenHands secrets (`YT_CLIENT_ID`, `YT_CLIENT_SECRET`,
`YT_CH1_REFRESH_TOKEN`..`YT_CH4_REFRESH_TOKEN`), fetched at run time.
