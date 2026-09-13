import unittest
from datetime import datetime, timezone, timedelta

from AKATH.runtime.runner_health_policy import evaluate_runner, HEARTBEAT_SECONDS, DEGRADED_SECONDS, OFFLINE_SECONDS, FAILOVER_SECONDS


class RunnerHealthPolicyTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 9, 6, 10, 0, 0, tzinfo=timezone.utc)

    def test_approved_timing(self):
        self.assertEqual(HEARTBEAT_SECONDS, 60)
        self.assertEqual(DEGRADED_SECONDS, 120)
        self.assertEqual(OFFLINE_SECONDS, 300)
        self.assertEqual(FAILOVER_SECONDS, 60)

    def test_online_with_fresh_heartbeat(self):
        result = evaluate_runner(self.now, self.now - timedelta(seconds=59))
        self.assertEqual(result["status"], "ONLINE")
        self.assertFalse(result["failover_ready"])

    def test_degraded_after_two_minutes(self):
        result = evaluate_runner(self.now, self.now - timedelta(seconds=121))
        self.assertEqual(result["status"], "DEGRADED")
        self.assertFalse(result["failover_ready"])

    def test_offline_after_five_minutes_requires_offline_detection(self):
        result = evaluate_runner(
            self.now,
            self.now - timedelta(seconds=301),
            offline_detected_at=self.now - timedelta(seconds=60),
        )
        self.assertEqual(result["status"], "OFFLINE")
        self.assertTrue(result["failover_ready"])

    def test_failover_waits_one_minute_after_offline_detection(self):
        result = evaluate_runner(
            self.now,
            self.now - timedelta(seconds=301),
            offline_detected_at=self.now - timedelta(seconds=59),
        )
        self.assertFalse(result["failover_ready"])

        result = evaluate_runner(
            self.now,
            self.now - timedelta(seconds=301),
            offline_detected_at=self.now - timedelta(seconds=60),
        )
        self.assertTrue(result["failover_ready"])

    def test_missing_heartbeat_is_unknown_not_offline(self):
        result = evaluate_runner(self.now, None)
        self.assertEqual(result["status"], "UNKNOWN")
        self.assertFalse(result["failover_ready"])


if __name__ == "__main__":
    unittest.main()
