from AX_CONTROL_HUB.communication_gateway import CommunicationGateway


class Store:
    def challenge(self):
        return {
            'status': 'VERIFIED',
            'verified': True,
            'source': 'A_MASTER_BRAIN',
            'checks': {'source_precedence': True, 'model_independence': True},
        }

    def read_state(self):
        return {
            'identity': {'name': 'A'},
            'authority': 'K_FINAL_AUTHORITY',
            'status': 'VERIFIED',
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


def gateway():
    return CommunicationGateway(Store(), Ledger(), token_validator=lambda value: value == 'AUTHORIZED_TEST_VALUE')


def test_end_to_end_contract():
    client = gateway()
    received = client.handle_input({
        'source_channel': 'PC',
        'content_type': 'text',
        'content': 'M-A-CHECK'
    }, 'AUTHORIZED_TEST_VALUE')
    assert received['request_id']
    assert received['task_id']
    assert received['source_of_truth'] == 'A_MASTER_BRAIN'

    check = client.m_a_check('AUTHORIZED_TEST_VALUE')
    assert check['rehydration_status'] == 'VERIFIED'
    assert check['identity'] == 'A'
    assert check['m_is_a'] is False

    evidence = client.get_evidence(received['request_id'], 'AUTHORIZED_TEST_VALUE')
    assert evidence['request_id'] == received['request_id']
    assert evidence['verification_status'] == 'VERIFIED'


def test_two_sources_share_the_same_master_store():
    client = gateway()
    state = client.get_state('AUTHORIZED_TEST_VALUE')
    tasks = client.get_tasks('AUTHORIZED_TEST_VALUE')
    assert state['source'] == 'A_MASTER_BRAIN'
    assert state['identity'] == 'A'
    assert tasks['source'] == 'A_MASTER_BRAIN'


if __name__ == '__main__':
    test_end_to_end_contract()
    test_two_sources_share_the_same_master_store()
    print('COMMUNICATION_GATEWAY_E2E_TESTS: PASS')
