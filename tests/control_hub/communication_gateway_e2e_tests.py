from pathlib import Path
from AX_CONTROL_HUB.communication_gateway import CommunicationGateway


class Store:
    def challenge(self):
        return {
            'status': 'VERIFIED',
            'verified': True,
            'source': 'A_MASTER_BRAIN',
            'runtime_profile': 'E2E',
            'checks': {'source_precedence': True, 'model_independence': True},
        }

    def read_state(self):
        return {
            'identity': {'name': 'A'},
            'authority': 'K_FINAL_AUTHORITY',
            'status': 'VERIFIED',
            'state_version': 0,
        }

    def read_tasks(self):
        return {'tasks': []}


class Ledger:
    def get(self, request_id):
        return {
            'request_id': request_id,
            'verification_status': 'VERIFIED',
            'execution_status': 'SUCCEEDED',
        }


class InputQueue:
    def __init__(self, root):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)

    def put(self, record):
        target = self.root / f"{record['request_id']}.json"
        if target.exists() and target.read_text(encoding='utf-8') != __import__('json').dumps(record, ensure_ascii=False, indent=2) + '\n':
            raise ValueError('REQUEST_ID_CONFLICT')
        target.write_text(__import__('json').dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    def get(self, request_id):
        target = self.root / f"{request_id}.json"
        return __import__('json').loads(target.read_text(encoding='utf-8')) if target.exists() else None


def gateway(tmp_path):
    return CommunicationGateway(
        Store(),
        Ledger(),
        token_validator=lambda value: value == 'AUTHORIZED_TEST_VALUE',
        input_queue=InputQueue(tmp_path),
    )


def test_end_to_end_contract(tmp_path):
    client = gateway(tmp_path)
    received = client.handle_input({
        'source_channel': 'PC',
        'content_type': 'text',
        'content': 'M-A-CHECK'
    }, 'AUTHORIZED_TEST_VALUE')
    assert received['request_id']
    assert received['task_id']
    assert received['source_of_truth'] == 'A_MASTER_BRAIN'
    assert received['transport_store'] == 'GATEWAY_INPUT_INBOX'
    assert client.get_input(received['request_id'], 'AUTHORIZED_TEST_VALUE')['content'] == 'M-A-CHECK'

    check = client.m_a_check('AUTHORIZED_TEST_VALUE')
    assert check['rehydration_status'] == 'VERIFIED'
    assert check['identity'] == 'A'
    assert check['m_is_a'] is False
    assert check['agent'] == 'M'

    evidence = client.get_evidence(received['request_id'], 'AUTHORIZED_TEST_VALUE')
    assert evidence['request_id'] == received['request_id']
    assert evidence['verification_status'] == 'VERIFIED'


def test_two_sources_share_the_same_master_store(tmp_path):
    client = gateway(tmp_path)
    state = client.get_state('AUTHORIZED_TEST_VALUE')
    tasks = client.get_tasks('AUTHORIZED_TEST_VALUE')
    assert state['source'] == 'A_MASTER_BRAIN'
    assert state['identity'] == 'A'
    assert state['state_version'] == 0
    assert tasks['source'] == 'A_MASTER_BRAIN'


if __name__ == '__main__':
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        test_end_to_end_contract(td)
        test_two_sources_share_the_same_master_store(td)
    print('COMMUNICATION_GATEWAY_E2E_TESTS: PASS')
