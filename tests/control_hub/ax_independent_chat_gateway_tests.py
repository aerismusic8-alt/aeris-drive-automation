import json
from pathlib import Path

from AX_CONTROL_HUB.communication_gateway import CommunicationGateway
from AX_CONTROL_HUB.gateway_input_queue import GatewayInputQueue

class Store:
    def __init__(self, verified=True): self.verified=verified
    def challenge(self): return {'status':'VERIFIED' if self.verified else 'PENDING_VERIFICATION','verified':self.verified,'source':'A_MASTER_BRAIN','runtime_profile':'TEST','checks':{'source_precedence':self.verified,'model_independence':self.verified}}
    def read_state(self): return {'identity':{'name':'A'},'identity_authority':'A_MASTER_BRAIN','authority':'K_FINAL_AUTHORITY','status':'VERIFIED','state_version':3,'model_independence':True}
    def read_tasks(self): return {'tasks':[]}
class Ledger:
    def get(self, request_id): return None
class InputQueue:
    def __init__(self,root): self.root=Path(root); self.root.mkdir(parents=True,exist_ok=True)
    def put(self,record):
        target=self.root/f"{record['request_id']}.json"
        if target.exists():
            existing=json.loads(target.read_text(encoding='utf-8'))
            if existing != record: raise ValueError('REQUEST_ID_CONFLICT')
            return
        target.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    def get(self,request_id):
        target=self.root/f"{request_id}.json"; return json.loads(target.read_text(encoding='utf-8')) if target.exists() else None
    def find_by_idempotency_key(self,key):
        for target in self.root.glob('*.json'):
            record=json.loads(target.read_text(encoding='utf-8'))
            if record.get('idempotency_key')==key: return record
        return None

def gateway(tmp_path,verified=True): return CommunicationGateway(Store(verified),Ledger(),token_validator=lambda value:value in {'K_TOKEN','SERVICE_TOKEN','READ_ONLY_TOKEN'},input_queue=InputQueue(tmp_path),identity_resolver=lambda value:{'K_TOKEN':'K','SERVICE_TOKEN':'SERVICE','READ_ONLY_TOKEN':'READ_ONLY'}[value])

def test_new_session_rehydrates_authoritative_context(tmp_path):
    result=gateway(tmp_path).create_session('K_TOKEN'); assert result['session_status']=='READY' and result['source_of_truth']=='A_MASTER_BRAIN' and result['identity']=='A' and result['state_version']==3

def test_service_and_read_only_capabilities_are_distinct(tmp_path):
    client=gateway(tmp_path); service=client.get_capabilities('SERVICE_TOKEN'); read_only=client.get_capabilities('READ_ONLY_TOKEN'); assert 'submit_input' in service['capabilities'] and 'submit_input' not in read_only['capabilities'] and service['identity']=='SERVICE' and read_only['identity']=='READ_ONLY'

def test_idempotency_key_rejects_duplicate_input(tmp_path):
    client=gateway(tmp_path); payload={'request_id':'req-1','idempotency_key':'idem-1','source_channel':'GPT','content_type':'text','content':'hello'}; assert client.handle_input(payload,'SERVICE_TOKEN')['status']=='RECEIVED'
    try: client.handle_input({**payload,'request_id':'req-2'},'SERVICE_TOKEN')
    except ValueError as exc: assert str(exc)=='DUPLICATE_IDEMPOTENCY_KEY'; return
    raise AssertionError('expected duplicate idempotency rejection')

def test_real_queue_rejects_racing_idempotency_key(tmp_path):
    queue=GatewayInputQueue(tmp_path); first={'request_id':'req-1','idempotency_key':'idem-1'}; queue.put(first)
    try: queue.put({'request_id':'req-2','idempotency_key':'idem-1'})
    except ValueError as exc: assert str(exc)=='DUPLICATE_IDEMPOTENCY_KEY'; return
    raise AssertionError('expected atomic duplicate rejection')

def test_unverified_rehydration_blocks_control_input(tmp_path):
    try: gateway(tmp_path,False).handle_input({'source_channel':'PC','content_type':'command','content':'health_check','idempotency_key':'x'},'K_TOKEN')
    except RuntimeError as exc: assert str(exc)=='REHYDRATION_REQUIRED'; return
    raise AssertionError('expected fail-closed rehydration rejection')

def test_read_only_cannot_submit_input(tmp_path):
    try: gateway(tmp_path).handle_input({'source_channel':'GPT','content_type':'text','content':'hello','idempotency_key':'x'},'READ_ONLY_TOKEN')
    except PermissionError as exc: assert str(exc)=='CAPABILITY_DENIED'; return
    raise AssertionError('expected capability rejection')

def test_raw_attachment_data_is_rejected(tmp_path):
    try: gateway(tmp_path).handle_input({'source_channel':'MOBILE','content_type':'image','idempotency_key':'x','attachments':[{'attachment_id':'a1','kind':'image','name':'x.png','media_type':'image/png','reference':'browser:a1','data':'BASE64'}]},'K_TOKEN')
    except ValueError as exc: assert str(exc)=='RAW_BINARY_NOT_ALLOWED'; return
    raise AssertionError('expected raw binary rejection')

def test_web_chat_surface_is_ax_not_aeris():
    html=Path(__file__).resolve().parents[2].joinpath('AX_CONTROL_HUB','operations.html').read_text(encoding='utf-8'); assert '<title>AX Web Chat</title>' in html and 'AERIS' not in html

if __name__=='__main__':
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        p=Path(td)
        for test in [test_new_session_rehydrates_authoritative_context,test_service_and_read_only_capabilities_are_distinct,test_idempotency_key_rejects_duplicate_input,test_real_queue_rejects_racing_idempotency_key,test_unverified_rehydration_blocks_control_input,test_read_only_cannot_submit_input,test_raw_attachment_data_is_rejected]: test(p)
    test_web_chat_surface_is_ax_not_aeris(); print('AX_INDEPENDENT_CHAT_GATEWAY_TESTS: PASS')
