import json
import os
from pathlib import Path

from AX_CONTROL_HUB.communication_gateway import CommunicationGateway


class Store:
    def __init__(self, verified=True):
        self.verified = verified

    def challenge(self):
        return {
            'status': 'VERIFIED' if self.verified else 'PENDING_VERIFICATION',
            'verified': self.verified,
            'source': 'A_MASTER_BRAIN',
            'runtime_profile': 'TEST',
            'checks': {'source_precedence': self.verified, 'model_independence': self.verified},
        }

    def read_state(self):
        return {
            'identity': {'name': 'A'},
            'authority': 'K_FINAL_AUTHORITY',
            'status': 'VERIFIED',
            'state_version': 3,
            'model_independence': True,
        }

    def read_tasks(self):
        return {'tasks': []}


class Ledger:
    def get(self, request_id):
        return None


class InputQueue:
    def __init__(self, root):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def put(self, record):
        target = self.root / f"{record['request_id']}.json"
        if target.exists():
            existing = json.loads(target.read_text(encoding='utf-8'))
            if existing != record:
                raise ValueError('REQUEST_ID_CONFLICT')
            return
        target.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    def get(self, request_id):
        target = self.root / f"{request_id}.json"
        if not target.exists():
            return None
        return json.loads(target.read_text(encoding='utf-8'))


def gateway(tmp_path, verified=True):
    return CommunicationGateway(
        Store(verified=verified),
        Ledger(),
        token_validator=lambda value: value in {'K_TOKEN', 'SERVICE_TOKEN', 'READ_ONLY_TOKEN'},
        input_queue=InputQueue(tmp_path),
    )


def test_new_session_rehydrates_authoritative_context(tmp_path):
    result = gateway(tmp_path).create_session('K_TOKEN')
    assert result['session_status'] == 'READY'
    assert result['source_of_truth'] == 'A_MASTER_BRAIN'
    assert result['identity'] == 'A'
    assert result['state_version'] == 3


def test_service_and_read_only_capabilities_are_distinct(tmp_path):
    client = gateway(tmp_path)
    service = client.get_capabilities('SERVICE_TOKEN')
    read_only = client.get_capabilities('READ_ONLY_TOKEN')
    assert 'submit_input' in service['capabilities']
    assert 'submit_input' not in read_only['capabilities']
    assert service['identity'] == 'SERVICE'
    assert read_only['identity'] == 'READ_ONLY'


def test_idempotency_key_rejects_duplicate_input(tmp_path):
    client = gateway(tmp_path)
    payload = {
        'request_id': 'req-1',
        'idempotency_key': 'idem-1',
        'source_channel': 'GPT',
        'content_type': 'text',
        'content': 'hello',
    }
    first = client.handle_input(payload, 'SERVICE_TOKEN')
    assert first['status'] == 'RECEIVED'
    try:
        client.handle_input({**payload, 'request_id': 'req-2'}, 'SERVICE_TOKEN')
    except ValueError as exc:
        assert str(exc) == 'DUPLICATE_IDEMPOTENCY_KEY'
        return
    raise AssertionError('expected duplicate idempotency rejection')


def test_unverified_rehydration_blocks_control_input(tmp_path):
    client = gateway(tmp_path, verified=False)
    try:
        client.handle_input({'source_channel': 'PC', 'content_type': 'command', 'content': 'health_check'}, 'K_TOKEN')
    except RuntimeError as exc:
        assert str(exc) == 'REHYDRATION_REQUIRED'
        return
    raise AssertionError('expected fail-closed rehydration rejection')


def test_raw_attachment_data_is_rejected(tmp_path):
    client = gateway(tmp_path)
    payload = {
        'source_channel': 'MOBILE',
        'content_type': 'image',
        'attachments': [{'attachment_id': 'a1', 'kind': 'image', 'name': 'x.png', 'media_type': 'image/png', 'reference': 'browser:a1', 'data': 'BASE64'}],
    }
    try:
        client.handle_input(payload, 'K_TOKEN')
    except ValueError as exc:
        assert str(exc) == 'RAW_BINARY_NOT_ALLOWED'
        return
    raise AssertionError('expected raw binary rejection')


def test_web_chat_surface_is_ax_not_aeris():
    html = Path(__file__).resolve().parents[2].joinpath('AX_CONTROL_HUB', 'operations.html').read_text(encoding='utf-8')
    assert '<title>AX Web Chat</title>' in html
    assert 'AERIS' not in html


if __name__ == '__main__':
    import tempfile
    tests = [
        test_new_session_rehydrates_authoritative_context,
        test_service_and_read_only_capabilities_are_distinct,
        test_idempotency_key_rejects_duplicate_input,
        test_unverified_rehydration_blocks_control_input,
        test_raw_attachment_data_is_rejected,
    ]
    with tempfile.TemporaryDirectory() as td:
        from pathlib import Path as P
        p = P(td)
        for test in tests:
            test(p)
    test_web_chat_surface_is_ax_not_aeris()
    print('AX_INDEPENDENT_CHAT_GATEWAY_TESTS: PASS')
