import json
import os
import tempfile
import unittest
from pathlib import Path

# The implementation is intentionally imported only after the test contract exists.
from ax_control_hub_server import MasterBrainStore, AuthStore, CommandLedger


class RuntimeContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.state = root / 'AX_MASTER_STATE.json'
        self.tasks = root / 'AX_MASTER_TASK_REGISTRY_v2.json'
        self.state.write_text(json.dumps({
            'status': 'INITIALIZED_PENDING_VERIFICATION',
            'authority': 'K_FINAL_AUTHORITY',
            'identity_authority': 'A_MASTER_BRAIN',
            'model_independence': True,
            'identity': {'name': 'A', 'role': 'AI Executive Orchestrator Master Brain'},
            'support_agent': {'name': 'M'},
        }), encoding='utf-8')
        self.tasks.write_text(json.dumps({'schema_version': '2.0', 'tasks': [{'id': 'T1', 'status': 'QUEUED'}]}), encoding='utf-8')
        self.store = MasterBrainStore(self.state, self.tasks)

    def tearDown(self):
        self.tmp.cleanup()

    def test_authoritative_state_is_loaded_without_synthesis(self):
        state = self.store.read_state()
        self.assertEqual(state['identity']['name'], 'A')
        self.assertEqual(state['identity_authority'], 'A_MASTER_BRAIN')

    def test_tasks_are_read_from_v2_registry(self):
        tasks = self.store.read_tasks()
        self.assertEqual(tasks['schema_version'], '2.0')
        self.assertEqual(tasks['tasks'][0]['id'], 'T1')

    def test_missing_source_fails_closed(self):
        missing = MasterBrainStore(self.state.with_name('missing.json'), self.tasks)
        with self.assertRaises(FileNotFoundError):
            missing.read_state()

    def test_password_verification_uses_adaptive_kdf(self):
        auth = AuthStore(iterations=210000)
        record = auth.create_user('K', 'test-password')
        self.assertTrue(auth.verify(record, 'test-password'))
        self.assertFalse(auth.verify(record, 'wrong-password'))
        self.assertNotEqual(record['salt'], '')
        self.assertEqual(record['algorithm'], 'PBKDF2-HMAC-SHA256')

    def test_idempotency_rejects_duplicate(self):
        ledger = CommandLedger()
        self.assertTrue(ledger.reserve('abc'))
        self.assertFalse(ledger.reserve('abc'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
