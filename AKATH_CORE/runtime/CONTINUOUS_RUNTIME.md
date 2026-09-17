# Continuous Runtime Contract

The bot is a persistent execution service, not a per-chat command runner.

1. K starts or explicitly shuts down the service.
2. The supervisor keeps cycling without requiring K to submit another command.
3. The planner must produce authorized next work rather than silently ending after one system task.
4. PowerShell is executed only through the allowlist.
5. Evidence and verification are mandatory before DONE.
6. Runtime heartbeat remains visible while idle or between jobs.
7. No production success is claimed from a system heartbeat task alone.
