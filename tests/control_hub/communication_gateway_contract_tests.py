import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / 'AX_CONTROL_HUB' / 'COMMUNICATION_GATEWAY_CONTRACT.json'


def test_contract_exists_and_declares_required_fields():
    data = json.loads(CONTRACT.read_text(encoding='utf-8'))
    assert data['schema_version'] == '1.0'
    assert {'request_id', 'source_channel', 'content_type'} <= set(data['request']['required'])
    assert {'request_id', 'status', 'rehydration_status', 'verification_status'} <= set(data['response']['required'])


def test_supported_input_channels_and_content_types_are_explicit():
    data = json.loads(CONTRACT.read_text(encoding='utf-8'))
    assert set(data['source_channels']) >= {'GPT', 'PC', 'MOBILE'}
    assert set(data['content_types']) >= {'text', 'file', 'image', 'event', 'command'}


if __name__ == '__main__':
    test_contract_exists_and_declares_required_fields()
    test_supported_input_channels_and_content_types_are_explicit()
    print('COMMUNICATION_GATEWAY_CONTRACT_TESTS: PASS')
