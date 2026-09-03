# AKATH Watchdog Contract

| Condition | Expected result |
|---|---|
| Fresh heartbeat | `HEALTHY`; no recovery |
| `RUNNING` with stale heartbeat | `RECOVERING` + recovery evidence |
| `VERIFIED` with old heartbeat | remain `VERIFIED`; no rollback |
| Missing state | `BLOCKED` + `SOURCE_STATE_UNAVAILABLE` |

The watchdog must never turn an unverified or unknown execution result into `VERIFIED`.