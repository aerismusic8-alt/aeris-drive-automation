from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HTML = ROOT / 'AX_CONTROL_HUB' / 'operations.html'
JS = ROOT / 'AX_CONTROL_HUB' / 'operations_client.js'
SERVER = ROOT / 'AX_CONTROL_HUB' / 'ax_control_hub_server.py'


def test_mobile_surface_exists():
    text = HTML.read_text(encoding='utf-8')
    assert 'viewport' in text
    assert '/gateway/input' in JS.read_text(encoding='utf-8')
    assert '/gateway/m-a-check' in JS.read_text(encoding='utf-8')
    assert '/operations_client.js' in SERVER.read_text(encoding='utf-8')


def test_client_supports_attachment_references_without_raw_binary_payloads():
    text = JS.read_text(encoding='utf-8')
    assert 'attachments' in text
    assert 'attachment_id' in text
    assert 'reference' in text
    assert "file.type.startsWith('image/')" in text
    assert 'file.arrayBuffer' not in text
    assert 'readAsArrayBuffer' not in text


def test_client_uses_gateway_token_for_protected_routes():
    text = JS.read_text(encoding='utf-8')
    assert 'Authorization' in text
    assert 'ax_gateway_token' in text


if __name__ == '__main__':
    test_mobile_surface_exists()
    test_client_supports_attachment_references_without_raw_binary_payloads()
    test_client_uses_gateway_token_for_protected_routes()
    print('OPERATIONS_SURFACE_TESTS: PASS')
