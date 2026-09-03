# A Communication Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single authenticated transport layer that lets GPT, PC, and Mobile submit text/files/media references and task commands to the existing A Master Brain-backed Control Hub and retrieve authoritative status without creating a second source of truth.

**Architecture:** Extend the existing local `AX_CONTROL_HUB` with a focused gateway module and HTTP routes. The gateway validates/normalizes requests, delegates state/task/evidence access to the existing `MasterBrainStore` and `CommandLedger`, and exposes a browser-friendly responsive client surface only after the API contract is proven. Binary content is represented by controlled references; authoritative state remains in A Master Brain.

**Tech Stack:** Python 3.11+, existing `http.server` runtime, JSON, PowerShell acceptance tests, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-03-a-communication-gateway-design.md`

## Global Constraints

- A Master Brain remains the single source of truth for identity, mission, decisions, tasks, state, evidence, and verification.
- Gateway state is transient transport/correlation metadata only.
- `M-A-CHECK` must rehydrate and verify A before authoritative A state is presented.
- `QUEUED != EXECUTING != COMPLETED`; completion requires evidence and verification.
- Unauthorized protected operations fail closed.
- Live financial execution remains disabled.
- File/image inputs use controlled references; do not write raw binary data into master state JSON.

---

### Task 1: Define the transport contract

**Files:**
- Create: `AX_CONTROL_HUB/COMMUNICATION_GATEWAY_CONTRACT.json`
- Test: `tests/control_hub/communication_gateway_contract_tests.py`

**Interfaces:**
- Produces a machine-readable request/response contract used by the gateway and client tests.
- Request fields: `request_id`, `task_id`, `source_channel`, `content_type`, `content`, `attachments`, `requested_at`.
- Attachment fields: `attachment_id`, `kind`, `name`, `media_type`, `reference`.
- Response fields: `request_id`, `task_id`, `status`, `rehydration_status`, `evidence_status`, `verification_status`.

- [ ] **Step 1: Write failing contract tests**

```python
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / 'AX_CONTROL_HUB' / 'COMMUNICATION_GATEWAY_CONTRACT.json'

def test_contract_exists_and_declares_required_fields():
    data = json.loads(CONTRACT.read_text(encoding='utf-8'))
    assert data['schema_version'] == '1.0'
    assert {'request_id','source_channel','content_type'} <= set(data['request']['required'])
    assert {'request_id','status','rehydration_status','verification_status'} <= set(data['response']['required'])

def test_supported_input_channels_and_content_types_are_explicit():
    data = json.loads(CONTRACT.read_text(encoding='utf-8'))
    assert set(data['source_channels']) >= {'GPT','PC','MOBILE'}
    assert set(data['content_types']) >= {'text','file','image','event','command'}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python tests/control_hub/communication_gateway_contract_tests.py`
Expected: FAIL because the contract file does not yet exist.

- [ ] **Step 3: Write the contract**

```json
{
  "schema_version": "1.0",
  "source_of_truth": "A_MASTER_BRAIN",
  "source_channels": ["GPT", "PC", "MOBILE", "SYSTEM"],
  "content_types": ["text", "file", "image", "event", "command"],
  "request": {
    "required": ["request_id", "source_channel", "content_type"],
    "fields": {
      "request_id": "string",
      "task_id": "string|null",
      "source_channel": "string",
      "content_type": "string",
      "content": "string|null",
      "attachments": "array",
      "requested_at": "string|null"
    },
    "attachment": ["attachment_id", "kind", "name", "media_type", "reference"]
  },
  "response": {
    "required": ["request_id", "status", "rehydration_status", "verification_status"],
    "statuses": ["RECEIVED", "QUEUED", "EXECUTING", "SUCCEEDED", "FAILED", "INTERRUPTED", "VERIFIED"],
    "rehydration_statuses": ["VERIFIED", "PENDING_VERIFICATION"],
    "verification_statuses": ["PENDING", "VERIFIED", "REJECTED"]
  },
  "security": {
    "protected_routes_require_authentication": true,
    "max_request_bytes": 1048576,
    "raw_binary_in_master_state": false,
    "live_financial_execution": false
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python tests/control_hub/communication_gateway_contract_tests.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_CONTROL_HUB/COMMUNICATION_GATEWAY_CONTRACT.json tests/control_hub/communication_gateway_contract_tests.py
git commit -m "test: define communication gateway contract"
```

### Task 2: Add the authenticated gateway and M-A-CHECK transport

**Files:**
- Create: `AX_CONTROL_HUB/communication_gateway.py`
- Modify: `AX_CONTROL_HUB/ax_control_hub_server.py`
- Test: `tests/control_hub/communication_gateway_tests.py`

**Interfaces:**
- `CommunicationGateway.handle_input(payload, auth_token) -> dict`
- `CommunicationGateway.get_state(auth_token) -> dict`
- `CommunicationGateway.get_tasks(auth_token) -> dict`
- `CommunicationGateway.get_evidence(request_id, auth_token) -> dict`
- `CommunicationGateway.m_a_check(auth_token) -> dict`
- The HTTP handler adds `/gateway/input`, `/gateway/state`, `/gateway/tasks`, `/gateway/evidence/<request_id>`, `/gateway/m-a-check`.

- [ ] **Step 1: Write failing tests for authentication, correlation, and rehydration**

```python
from AX_CONTROL_HUB.communication_gateway import CommunicationGateway

class FakeStore:
    def challenge(self):
        return {'status':'VERIFIED','verified':True,'source':'A_MASTER_BRAIN'}
    def read_state(self):
        return {'identity':{'name':'A'},'authority':'K_FINAL_AUTHORITY'}
    def read_tasks(self):
        return {'tasks':[]}

class FakeLedger:
    def get(self, request_id):
        return {'request_id':request_id,'verification_status':'VERIFIED'}

def test_input_gets_request_id_and_task_id():
    gateway = CommunicationGateway(FakeStore(), FakeLedger())
    result = gateway.handle_input({'source_channel':'GPT','content_type':'text','content':'hello'}, 'K')
    assert result['request_id']
    assert result['task_id']
    assert result['status'] == 'RECEIVED'

def test_m_a_check_returns_verified_rehydration():
    gateway = CommunicationGateway(FakeStore(), FakeLedger())
    result = gateway.m_a_check('K')
    assert result['rehydration_status'] == 'VERIFIED'
    assert result['identity'] == 'A'

def test_unauthorized_request_is_rejected():
    gateway = CommunicationGateway(FakeStore(), FakeLedger())
    try:
        gateway.get_state('BAD')
    except PermissionError:
        return
    raise AssertionError('expected PermissionError')
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python tests/control_hub/communication_gateway_tests.py`
Expected: FAIL because the gateway module and methods do not exist.

- [ ] **Step 3: Implement the minimal gateway**

```python
from __future__ import annotations
import secrets
from typing import Any

class CommunicationGateway:
    def __init__(self, store, ledger, max_request_bytes=1024*1024):
        self.store = store
        self.ledger = ledger
        self.max_request_bytes = max_request_bytes
        self._tokens = {'K'}

    def _auth(self, token):
        if token not in self._tokens:
            raise PermissionError('AUTH_REQUIRED')

    def handle_input(self, payload, auth_token):
        self._auth(auth_token)
        if not isinstance(payload, dict):
            raise ValueError('INVALID_REQUEST')
        source = str(payload.get('source_channel',''))
        content_type = str(payload.get('content_type',''))
        if source not in {'GPT','PC','MOBILE','SYSTEM'}:
            raise ValueError('INVALID_SOURCE_CHANNEL')
        if content_type not in {'text','file','image','event','command'}:
            raise ValueError('INVALID_CONTENT_TYPE')
        request_id = str(payload.get('request_id') or secrets.token_urlsafe(16))
        task_id = str(payload.get('task_id') or secrets.token_urlsafe(12))
        return {
            'request_id': request_id,
            'task_id': task_id,
            'status': 'RECEIVED',
            'rehydration_status': self.store.challenge()['status'],
            'evidence_status': 'PENDING',
            'verification_status': 'PENDING'
        }

    def get_state(self, auth_token):
        self._auth(auth_token)
        state = self.store.read_state()
        challenge = self.store.challenge()
        return {
            'source':'A_MASTER_BRAIN',
            'identity':state.get('identity',{}).get('name'),
            'authority':state.get('authority'),
            'rehydration_status':challenge['status']
        }

    def get_tasks(self, auth_token):
        self._auth(auth_token)
        return {'source':'A_MASTER_BRAIN','tasks':self.store.read_tasks().get('tasks',[])}

    def get_evidence(self, request_id, auth_token):
        self._auth(auth_token)
        record = self.ledger.get(request_id)
        if record is None:
            raise LookupError('EVIDENCE_UNAVAILABLE')
        return record

    def m_a_check(self, auth_token):
        self._auth(auth_token)
        state = self.store.read_state()
        challenge = self.store.challenge()
        return {
            'rehydration_status':challenge['status'],
            'identity':state.get('identity',{}).get('name'),
            'authority':state.get('authority'),
            'source':'A_MASTER_BRAIN',
            'm_is_a':False
        }
```

- [ ] **Step 4: Integrate routes without duplicating persistence**

Modify `ax_control_hub_server.py` to instantiate one `CommunicationGateway(STORE, LEDGER)` and delegate gateway routes to it. Do not create another state file, task registry, or evidence database.

- [ ] **Step 5: Run tests to verify they pass**

Run: `python tests/control_hub/communication_gateway_tests.py`
Expected: PASS.

- [ ] **Step 6: Run the existing Control Hub regression suite**

Run: `python tests/control_hub/runtime_unit_tests.py && python tests/control_hub/runtime_integration_tests.py`
Expected: PASS with existing `/state`, `/tasks`, `/m-a-check`, and `/evidence` behavior preserved.

- [ ] **Step 7: Commit**

```bash
git add AX_CONTROL_HUB/communication_gateway.py AX_CONTROL_HUB/ax_control_hub_server.py tests/control_hub/communication_gateway_tests.py
git commit -m "feat: add authenticated A communication gateway"
```

### Task 3: Add PC/Mobile client surface and attachment-reference handling

**Files:**
- Create: `AX_CONTROL_HUB/operations.html`
- Create: `AX_CONTROL_HUB/operations_client.js`
- Modify: `AX_CONTROL_HUB/communication_gateway.py`
- Test: `tests/control_hub/operations_surface_tests.py`

**Interfaces:**
- Browser POST target: `/gateway/input`
- Browser GET targets: `/gateway/state`, `/gateway/tasks`, `/gateway/evidence/<request_id>`
- Attachment handling returns references only; no raw binary is written to `AX_MASTER_STATE.json`.

- [ ] **Step 1: Write failing surface tests**

```python
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HTML = ROOT / 'AX_CONTROL_HUB' / 'operations.html'
JS = ROOT / 'AX_CONTROL_HUB' / 'operations_client.js'

def test_mobile_surface_exists():
    text = HTML.read_text(encoding='utf-8')
    assert 'viewport' in text
    assert '/gateway/input' in text
    assert '/gateway/m-a-check' in text

def test_client_accepts_text_and_attachment_reference():
    text = JS.read_text(encoding='utf-8')
    assert 'attachments' in text
    assert 'content_type' in text
    assert 'task_id' in text
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python tests/control_hub/operations_surface_tests.py`
Expected: FAIL because the browser surface files do not exist.

- [ ] **Step 3: Add the responsive Operations Hub**

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AERIS / AX Operations Hub</title>
<style>body{font-family:system-ui,sans-serif;max-width:960px;margin:auto;padding:16px}textarea{width:100%;min-height:120px}button,input{font-size:1rem;padding:10px}section{margin:16px 0;padding:12px;border:1px solid #ccc;border-radius:8px}</style>
</head>
<body>
<h1>AERIS / AX Operations Hub</h1>
<section><button id="check">M-A-CHECK</button><pre id="state"></pre></section>
<section><textarea id="message" placeholder="ข้อความหรือคำสั่ง"></textarea><input id="file" type="file" multiple><button id="send">Send</button><pre id="result"></pre></section>
<script src="operations_client.js"></script>
</body>
</html>
```

- [ ] **Step 4: Implement the browser client**

```javascript
async function api(path, options={}) {
  const response = await fetch(path, {
    ...options,
    headers: {'Content-Type':'application/json', ...(options.headers || {})}
  });
  if (!response.ok) throw new Error(`HTTP_${response.status}`);
  return response.json();
}

document.getElementById('check').onclick = async () => {
  document.getElementById('state').textContent = JSON.stringify(await api('/gateway/m-a-check',{method:'POST',body:'{}'}), null, 2);
};

document.getElementById('send').onclick = async () => {
  const files = [...document.getElementById('file').files].map(file => ({
    attachment_id: crypto.randomUUID(), kind: file.type.startsWith('image/') ? 'image' : 'file',
    name: file.name, media_type: file.type || 'application/octet-stream', reference: `browser:${crypto.randomUUID()}`
  }));
  const payload = {source_channel:'MOBILE',content_type:files.length ? 'file' : 'text',content:document.getElementById('message').value,attachments:files};
  document.getElementById('result').textContent = JSON.stringify(await api('/gateway/input',{method:'POST',body:JSON.stringify(payload)}), null, 2);
};
```

- [ ] **Step 5: Expose the static surface only after authentication policy is respected**

Serve `operations.html` from the existing Control Hub as an authenticated Operations Hub view. Do not expose unrestricted command operations from the page.

- [ ] **Step 6: Run surface and regression tests**

Run: `python tests/control_hub/operations_surface_tests.py && python tests/control_hub/runtime_unit_tests.py && python tests/control_hub/runtime_integration_tests.py`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add AX_CONTROL_HUB/operations.html AX_CONTROL_HUB/operations_client.js AX_CONTROL_HUB/communication_gateway.py tests/control_hub/operations_surface_tests.py
git commit -m "feat: add responsive PC mobile operations surface"
```

### Task 4: Add end-to-end gateway acceptance gates and documentation

**Files:**
- Create: `tests/control_hub/communication_gateway_e2e_tests.py`
- Modify: `.github/workflows/ax-control-hub-tests.yml`
- Modify: `AX_CONTROL_HUB/API_CONTRACT.md`
- Modify: `README.md`

**Interfaces:**
- Acceptance test proves one logical flow: `client -> gateway -> A rehydration -> request correlation -> evidence lookup`.
- Workflow gate is additive and must fail if source-of-truth, authentication, or state separation is broken.

- [ ] **Step 1: Write failing E2E assertions**

```python
def test_end_to_end_contract():
    from AX_CONTROL_HUB.communication_gateway import CommunicationGateway

    class Store:
        def challenge(self): return {'status':'VERIFIED','verified':True}
        def read_state(self): return {'identity':{'name':'A'},'authority':'K_FINAL_AUTHORITY'}
        def read_tasks(self): return {'tasks':[]}
    class Ledger:
        def get(self, request_id): return {'request_id':request_id,'verification_status':'VERIFIED'}

    gateway = CommunicationGateway(Store(), Ledger())
    received = gateway.handle_input({'source_channel':'PC','content_type':'text','content':'hello'}, 'K')
    assert received['request_id']
    assert received['task_id']
    check = gateway.m_a_check('K')
    assert check['rehydration_status'] == 'VERIFIED'
    assert check['identity'] == 'A'
    assert check['m_is_a'] is False
```

- [ ] **Step 2: Run the test to verify it fails before the full implementation is complete**

Run: `python tests/control_hub/communication_gateway_e2e_tests.py`
Expected: FAIL until Tasks 2-3 are complete.

- [ ] **Step 3: Add the E2E test to the Control Hub workflow**

Add a workflow step:

```yaml
      - name: Run communication gateway E2E acceptance
        run: python tests/control_hub/communication_gateway_e2e_tests.py
```

- [ ] **Step 4: Document the new transport path**

Update `AX_CONTROL_HUB/API_CONTRACT.md` with `/gateway/input`, `/gateway/m-a-check`, `/gateway/state`, `/gateway/tasks`, and `/gateway/evidence/{request_id}` plus the explicit rule that the gateway is not a source of truth.

Update `README.md` to expose the Operations Hub entry point and describe it as a PC/Mobile client surface over A Master Brain, not a replacement for A Master Brain.

- [ ] **Step 5: Run the full acceptance suite locally**

Run: `python tests/control_hub/communication_gateway_contract_tests.py && python tests/control_hub/communication_gateway_tests.py && python tests/control_hub/operations_surface_tests.py && python tests/control_hub/communication_gateway_e2e_tests.py && python tests/control_hub/runtime_unit_tests.py && python tests/control_hub/runtime_integration_tests.py`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tests/control_hub/communication_gateway_e2e_tests.py .github/workflows/ax-control-hub-tests.yml AX_CONTROL_HUB/API_CONTRACT.md README.md
git commit -m "test: gate PC mobile communication gateway end to end"
```

### Verification checkpoint

After Task 4, GitHub Actions must pass the gateway tests plus the pre-existing rehydration, continuity, File ID, evidence, restart, write-back, and interruption-resume acceptance suite. Only then may the PC/Mobile gateway be labeled `VERIFIED` for its transport contract. Real business execution and real revenue remain separate acceptance gates.
