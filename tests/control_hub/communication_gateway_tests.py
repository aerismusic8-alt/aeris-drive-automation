from AX_CONTROL_HUB.communication_gateway import CommunicationGateway


class FakeStore:
    def challenge(self):
        return {'status': 'VERIFIED', 'verified': True, 'source': 'A_MASTER_BRAIN', 'runtime_profile': 'TEST'}

    def read_state(self):
        return {'identity': {'name': 'A'}, 'authority': 'K_FINAL_AUTHORITY', 'state_version': 0}

    def read_tasks(self):
        return {'tasks': []}


class FakeLedger:
    def get(self, request_id):
        return {'request_id': request_id, 'verification_status': 'VERIFIED'}


class FakeInputQueue:
    def __init__(self):
        self.records = {}

    def put(self, record):
        existing = self.records.get(record['request_id'])
        if existing is not None and existing != record:
            raise ValueError('REQUEST_ID_CONFLICT')
        self.records[record['request_id']] = record

    def get(self, request_id):
        return self.records.get(request_id)


def make_gateway():
    return CommunicationGateway(FakeStore(), FakeLedger(), token_validator=lambda value: value == 'AUTHORIZED_TEST_VALUE', input_queue=FakeInputQueue())


def test_input_gets_request_id_and_task_id_and_is_persisted():
    gateway = make_gateway()
    result = gateway.handle_input({'source_channel': 'GPT', 'content_type': 'text', 'content': 'hello'}, 'AUTHORIZED_TEST_VALUE')
    assert result['request_id']
    assert result['task_id']
    assert result['status'] == 'RECEIVED'
    assert result['rehydration_status'] == 'VERIFIED'
    assert result['verification_status'] == 'PENDING'
    assert gateway.get_input(result['request_id'], 'AUTHORIZED_TEST_VALUE')['content'] == 'hello'


def test_existing_task_id_is_preserved():
    gateway = make_gateway()
    result = gateway.handle_input({'source_channel': 'PC', 'content_type': 'event', 'task_id': 'TASK-1'}, 'AUTHORIZED_TEST_VALUE')
    assert result['task_id'] == 'TASK-1'


def test_attachments_are_references_not_binary_state():
    gateway = make_gateway()
    result = gateway.handle_input({
        'source_channel': 'MOBILE',
        'content_type': 'image',
        'attachments': [{
            'attachment_id': 'ATT-1',
            'kind': 'image',
            'name': 'cover.png',
            'media_type': 'image/png',
            'reference': 'browser:ATT-1'
        }]
    }, 'AUTHORIZED_TEST_VALUE')
    assert result['attachments'][0]['reference'] == 'browser:ATT-1'
    assert 'bytes' not in result['attachments'][0]


def test_m_a_check_returns_verified_rehydration_without_impersonation():
    gateway = make_gateway()
    result = gateway.m_a_check('AUTHORIZED_TEST_VALUE')
    assert result['rehydration_status'] == 'VERIFIED'
    assert result['identity'] == 'A'
    assert result['m_is_a'] is False
    assert result['agent'] == 'M'


def test_unauthorized_request_is_rejected():
    gateway = make_gateway()
    try:
        gateway.get_state('UNAUTHORIZED_TEST_VALUE')
    except PermissionError as exc:
        assert str(exc) == 'AUTH_REQUIRED'
        return
    raise AssertionError('expected PermissionError')


def test_invalid_channel_and_content_type_are_rejected():
    gateway = make_gateway()
    for payload in (
        {'source_channel': 'UNKNOWN', 'content_type': 'text'},
        {'source_channel': 'GPT', 'content_type': 'unsupported'},
    ):
        try:
            gateway.handle_input(payload, 'AUTHORIZED_TEST_VALUE')
        except ValueError as exc:
            assert str(exc) in {'INVALID_SOURCE_CHANNEL', 'INVALID_CONTENT_TYPE'}
        else:
            raise AssertionError('expected ValueError')


if __name__ == '__main__':
    test_input_gets_request_id_and_task_id_and_is_persisted()
    test_existing_task_id_is_preserved()
    test_attachments_are_references_not_binary_state()
    test_m_a_check_returns_verified_rehydration_without_impersonation()
    test_unauthorized_request_is_rejected()
    test_invalid_channel_and_content_type_are_rejected()
    print('COMMUNICATION_GATEWAY_TESTS: PASS')
