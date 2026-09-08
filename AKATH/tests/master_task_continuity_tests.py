import unittest

from AKATH.runtime.ax_rehydration_adapter import extract_current_work, validate_current_work


class MasterTaskContinuityTests(unittest.TestCase):
    def registry(self):
        return {
            "schema_version": "2.1",
            "registry_role": "AUTHORITATIVE_MASTER_TASK_STATUS",
            "current_work": {
                "active": True,
                "task_id": "AICS-LIVE-TRADING",
                "name": "XM Strategy & Revenue Pipeline",
                "execution_status": "NON-LIVE / GUARDRAIL",
            },
            "tasks": [
                {"task": "AICS-LIVE-TRADING", "approval": "APPROVED", "execution": "NON-LIVE / GUARDRAIL"}
            ],
        }

    def test_current_work_references_existing_task_id(self):
        result = validate_current_work(self.registry())
        self.assertTrue(result["valid"])
        self.assertEqual(result["task_id"], "AICS-LIVE-TRADING")

    def test_rehydration_extracts_same_current_work(self):
        result = extract_current_work(self.registry())
        self.assertEqual(result["task_id"], "AICS-LIVE-TRADING")
        self.assertEqual(result["name"], "XM Strategy & Revenue Pipeline")

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


if __name__ == "__main__":
    unittest.main()
