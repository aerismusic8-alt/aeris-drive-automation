import unittest

from AKATH.runtime.ax_rehydration_adapter import (
    extract_current_work,
    get_task_by_id,
    validate_current_work,
    validate_task_registry,
)


class MasterTaskContinuityTests(unittest.TestCase):
    def registry(self):
        return {
            "schema_version": "2.2",
            "registry_role": "AUTHORITATIVE_MASTER_TASK_STATUS",
            "current_work": {"active": True, "task_id": "AICS-LIVE-TRADING"},
            "tasks": [
                {
                    "task_id": "AICS-LIVE-TRADING",
                    "name": "XM Strategy & Revenue Pipeline",
                    "objective": "Build and verify the guarded XM revenue pipeline.",
                    "priority": "P1_REVENUE",
                    "approval_status": "APPROVED",
                    "execution_status": "NON-LIVE / GUARDRAIL",
                    "timestamp": "2026-09-08T08:43:54+07:00",
                    "details": {
                        "current_step": "CONTROL_PLANE_BLOCKER_REPAIR",
                        "next_step": "RUN_SELF_HOSTED_XM_VERIFICATION",
                        "approval_required_next": "STRATEGY_ACTIVATION_K",
                        "worker": "AX",
                        "output": [],
                        "evidence": [],
                        "verification": [],
                        "blockers": [],
                        "retry_fallback": [],
                        "business_revenue_state": "ACTIVE / NON-LIVE",
                    },
                }
            ],
        }

    def test_current_work_references_existing_task_id(self):
        result = validate_current_work(self.registry())
        self.assertTrue(result["valid"])
        self.assertEqual(result["task_id"], "AICS-LIVE-TRADING")

    def test_rehydration_extracts_canonical_task_details(self):
        result = extract_current_work(self.registry())
        self.assertEqual(result["task_id"], "AICS-LIVE-TRADING")
        self.assertEqual(result["name"], "XM Strategy & Revenue Pipeline")
        self.assertEqual(result["details"]["current_step"], "CONTROL_PLANE_BLOCKER_REPAIR")

    def test_task_lookup_returns_same_canonical_record(self):
        task = get_task_by_id(self.registry(), "AICS-LIVE-TRADING")
        self.assertEqual(task["task_id"], "AICS-LIVE-TRADING")
        self.assertEqual(task["details"]["next_step"], "RUN_SELF_HOSTED_XM_VERIFICATION")

    def test_missing_current_work_fails_closed(self):
        registry = self.registry()
        registry.pop("current_work")
        result = validate_current_work(registry)
        self.assertFalse(result["valid"])
        self.assertIn("CURRENT_WORK_MISSING", result["errors"])

    def test_current_work_cannot_reference_unknown_task(self):
        registry = self.registry()
        registry["current_work"]["task_id"] = "UNKNOWN-TASK"
        result = validate_current_work(registry)
        self.assertFalse(result["valid"])
        self.assertIn("CURRENT_WORK_TASK_NOT_FOUND", result["errors"])

    def test_duplicate_task_ids_fail_closed(self):
        registry = self.registry()
        registry["tasks"].append(dict(registry["tasks"][0]))
        result = validate_task_registry(registry)
        self.assertFalse(result["valid"])
        self.assertIn("DUPLICATE_TASK_ID", result["errors"])

    def test_legacy_task_name_without_task_id_fails_closed(self):
        registry = self.registry()
        registry["tasks"] = [{"task": "AICS-LIVE-TRADING"}]
        result = validate_task_registry(registry)
        self.assertFalse(result["valid"])
        self.assertIn("TASK_ID_MISSING", result["errors"])

    def test_registry_count_is_exact_and_not_padded(self):
        registry = self.registry()
        result = validate_task_registry(registry)
        self.assertTrue(result["valid"])
        self.assertEqual(result["task_count"], 1)


if __name__ == "__main__":
    unittest.main()
