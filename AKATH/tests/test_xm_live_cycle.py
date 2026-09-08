from datetime import datetime, timezone


def test_normalize_status_marks_missing_heartbeat_as_kill():
    from xm_live_cycle import normalize_status
    result = normalize_status({"ok": True, "heartbeat": None}, now=datetime.now(timezone.utc))
    assert result["sentinel"]["decision"] == "KILL"
    assert result["report"]["next_action"] == "KILL"
