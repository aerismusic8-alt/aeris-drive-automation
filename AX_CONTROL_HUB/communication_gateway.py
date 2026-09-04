from __future__ import annotations

import re
import secrets
from typing import Any, Callable

_ALLOWED_SOURCES={'GPT','PC','MOBILE','SYSTEM','WEB'}
_ALLOWED_CONTENT_TYPES={'text','file','image','event','command'}
_MAX_INPUT_LENGTH=1_048_576
_ID_PATTERN=re.compile(r'^[A-Za-z0-9._:-]{1,128}$')
_CAPABILITIES={'K':{'read_state','read_tasks','read_evidence','submit_input','m_a_check'},'SERVICE':{'read_state','read_tasks','read_evidence','submit_input','m_a_check'},'READ_ONLY':{'read_state','read_tasks','read_evidence','m_a_check'}}

class CommunicationGateway:
    """Transport-only gateway over the existing A Master Brain stores."""
    def __init__(self,store:Any,ledger:Any,token_validator:Callable[[str],bool],input_queue:Any,max_input_length:int=_MAX_INPUT_LENGTH,identity_resolver:Callable[[str],str]|None=None):
        self.store=store; self.ledger=ledger; self.token_validator=token_validator; self.input_queue=input_queue; self.max_input_length=max_input_length; self.identity_resolver=identity_resolver or (lambda _token:'K')
    def _auth(self,token:str)->str:
        if not token or not self.token_validator(token): raise PermissionError('AUTH_REQUIRED')
        identity=str(self.identity_resolver(token))
        if identity not in _CAPABILITIES: raise PermissionError('IDENTITY_UNAUTHORIZED')
        return identity
    def _require(self,token:str,capability:str)->str:
        identity=self._auth(token)
        if capability not in _CAPABILITIES[identity]: raise PermissionError('CAPABILITY_DENIED')
        return identity
    @staticmethod
    def _identifier(value:Any,error_code:str)->str:
        value=str(value or '').strip()
        if not _ID_PATTERN.fullmatch(value): raise ValueError(error_code)
        return value
    def _validate_payload(self,payload:dict[str,Any])->None:
        if not isinstance(payload,dict): raise ValueError('INVALID_REQUEST')
        if str(payload.get('source_channel','')) not in _ALLOWED_SOURCES: raise ValueError('INVALID_SOURCE_CHANNEL')
        if str(payload.get('content_type','')) not in _ALLOWED_CONTENT_TYPES: raise ValueError('INVALID_CONTENT_TYPE')
        content=payload.get('content')
        if content is not None and not isinstance(content,str): raise ValueError('INVALID_CONTENT')
        if isinstance(content,str) and len(content.encode('utf-8'))>self.max_input_length: raise ValueError('REQUEST_TOO_LARGE')
        attachments=payload.get('attachments',[])
        if not isinstance(attachments,list): raise ValueError('INVALID_ATTACHMENTS')
        for item in attachments:
            if not isinstance(item,dict): raise ValueError('INVALID_ATTACHMENT')
            if not {'attachment_id','kind','name','media_type','reference'} <= set(item): raise ValueError('INVALID_ATTACHMENT')
            if 'bytes' in item or 'data' in item: raise ValueError('RAW_BINARY_NOT_ALLOWED')
    def create_session(self,auth_token:str)->dict[str,Any]:
        identity=self._auth(auth_token); challenge=self.store.challenge(); state=self.store.read_state(); ready=bool(challenge.get('verified') and challenge.get('source')=='A_MASTER_BRAIN')
        return {'session_status':'READY' if ready else 'BLOCKED','identity':state.get('identity',{}).get('name'),'identity_authority':state.get('identity_authority'),'authority':state.get('authority'),'state_version':int(state.get('state_version',0)),'source_of_truth':'A_MASTER_BRAIN','rehydration_status':challenge.get('status'),'caller_identity':identity,'model_independence':state.get('model_independence') is True}
    def get_capabilities(self,auth_token:str)->dict[str,Any]:
        identity=self._auth(auth_token); return {'identity':identity,'capabilities':sorted(_CAPABILITIES[identity]),'source_of_truth':'A_MASTER_BRAIN','model_identity_is_ax_identity':False}
    def handle_input(self,payload:dict[str,Any],auth_token:str)->dict[str,Any]:
        self._require(auth_token,'submit_input'); self._validate_payload(payload); challenge=self.store.challenge()
        if not challenge.get('verified') or challenge.get('source')!='A_MASTER_BRAIN': raise RuntimeError('REHYDRATION_REQUIRED')
        request_id=self._identifier(payload.get('request_id') or secrets.token_urlsafe(16),'INVALID_REQUEST_ID'); idempotency_key=self._identifier(payload.get('idempotency_key'),'IDEMPOTENCY_KEY_REQUIRED')
        if hasattr(self.input_queue,'find_by_idempotency_key') and self.input_queue.find_by_idempotency_key(idempotency_key) is not None: raise ValueError('DUPLICATE_IDEMPOTENCY_KEY')
        task_id=self._identifier(payload.get('task_id') or secrets.token_urlsafe(12),'INVALID_TASK_ID')
        record={'request_id':request_id,'task_id':task_id,'idempotency_key':idempotency_key,'status':'RECEIVED','source_channel':str(payload['source_channel']),'content_type':str(payload['content_type']),'content':payload.get('content'),'rehydration_status':challenge['status'],'evidence_status':'PENDING','verification_status':'PENDING','attachments':[dict(item) for item in payload.get('attachments',[])],'source_of_truth':'A_MASTER_BRAIN','transport_store':'GATEWAY_INPUT_INBOX','runtime_profile':challenge.get('runtime_profile')}
        try:self.input_queue.put(record)
        except ValueError as exc:
            if str(exc) in {'REQUEST_ID_CONFLICT','DUPLICATE_IDEMPOTENCY_KEY'}: raise ValueError(str(exc)) from exc
            raise
        return record
    def get_input(self,request_id:str,auth_token:str)->dict[str,Any]:
        self._require(auth_token,'read_evidence'); record=self.input_queue.get(request_id)
        if record is None: raise LookupError('INPUT_UNAVAILABLE')
        return record
    def get_state(self,auth_token:str)->dict[str,Any]:
        self._require(auth_token,'read_state'); state=self.store.read_state(); challenge=self.store.challenge(); return {'source':'A_MASTER_BRAIN','identity':state.get('identity',{}).get('name'),'identity_under_test':'A','authority':state.get('authority'),'master_status':state.get('status'),'state_version':int(state.get('state_version',0)),'last_verified_evidence':state.get('last_verified_evidence'),'rehydration_status':challenge['status'],'model_independence':state.get('model_independence') is True,'runtime_profile':challenge.get('runtime_profile')}
    def get_tasks(self,auth_token:str)->dict[str,Any]:
        self._require(auth_token,'read_tasks'); return {'source':'A_MASTER_BRAIN','tasks':self.store.read_tasks().get('tasks',[])}
    def get_evidence(self,request_id:str,auth_token:str)->dict[str,Any]:
        self._require(auth_token,'read_evidence'); record=self.ledger.get(request_id)
        if record is None: raise LookupError('EVIDENCE_UNAVAILABLE')
        return record
    def m_a_check(self,auth_token:str)->dict[str,Any]:
        self._require(auth_token,'m_a_check'); state=self.store.read_state(); challenge=self.store.challenge(); return {'rehydration_status':challenge['status'],'verified':challenge['verified'],'identity':state.get('identity',{}).get('name'),'identity_under_test':'A','agent':'M','authority':state.get('authority'),'source':'A_MASTER_BRAIN','m_is_a':False,'runtime_profile':challenge.get('runtime_profile'),'checks':challenge.get('checks',{})}
