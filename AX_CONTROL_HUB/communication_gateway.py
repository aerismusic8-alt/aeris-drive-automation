from __future__ import annotations

import secrets
from typing import Any, Callable


_ALLOWED_SOURCES = {'GPT', 'PC', 'MOBILE', 'SYSTEM'}
_ALLOWED_CONTENT_TYPES = {'text', 'file', 'image', 'event', 'command'}
_MAX_INPUT_LENGTH = 1_048_576


class CommunicationGateway:
    """Transport-only gateway over the existing A Master Brain stores."""

    def __init__(self, store: Any, ledger: Any, token_validator: Callable[[str], bool], max_input_length: int = _MAX_INPUT_LENGTH):
        self.store = store
        self.ledger = ledger
        self.token_validator = token_validator
        self.max_input_length = max_input_length

    def _auth(self, token: str) -> None:
        if not token or not self.token_validator(token):
            raise PermissionError('AUTH_REQUIRED')

    def _validate_payload(self, payload: dict[str, Any]) -> None:
        if not isinstance(payload, dict):
            raise ValueError('INVALID_REQUEST')
        source = str(payload.get('source_channel', ''))
        content_type = str(payload.get('content_type', ''))
        if source not in _ALLOWED_SOURCES:
            raise ValueError('INVALID_SOURCE_CHANNEL')
        if content_type not in _ALLOWED_CONTENT_TYPES:
            raise ValueError('INVALID_CONTENT_TYPE')
        content = payload.get('content')
        if content is not None and not isinstance(content, str):
            raise ValueError('INVALID_CONTENT')
        if isinstance(content, str) and len(content.encode('utf-8')) > self.max_input_length:
            raise ValueError('REQUEST_TOO_LARGE')
        attachments = payload.get('attachments', [])
        if not isinstance(attachments, list):
            raise ValueError('INVALID_ATTACHMENTS')
        for item in attachments:
            if not isinstance(item, dict):
                raise ValueError('INVALID_ATTACHMENT')
            required = {'attachment_id', 'kind', 'name', 'media_type', 'reference'}
            if not required <= set(item):
                raise ValueError('INVALID_ATTACHMENT')
            if 'bytes' in item or 'data' in item:
                raise ValueError('RAW_BINARY_NOT_ALLOWED')

    def handle_input(self, payload: dict[str, Any], auth_token: str) -> dict[str, Any]:
        self._auth(auth_token)
        self._validate_payload(payload)
        challenge = self.store.challenge()
        request_id = str(payload.get('request_id') or secrets.token_urlsafe(16))
        task_id = str(payload.get('task_id') or secrets.token_urlsafe(12))
        attachments = [dict(item) for item in payload.get('attachments', [])]
        return {
            'request_id': request_id,
            'task_id': task_id,
            'status': 'RECEIVED',
            'source_channel': str(payload['source_channel']),
            'content_type': str(payload['content_type']),
            'rehydration_status': challenge['status'],
            'evidence_status': 'PENDING',
            'verification_status': 'PENDING',
            'attachments': attachments,
            'source_of_truth': 'A_MASTER_BRAIN',
        }

    def get_state(self, auth_token: str) -> dict[str, Any]:
        self._auth(auth_token)
        state = self.store.read_state()
        challenge = self.store.challenge()
        return {
            'source': 'A_MASTER_BRAIN',
            'identity': state.get('identity', {}).get('name'),
            'authority': state.get('authority'),
            'master_status': state.get('status'),
            'rehydration_status': challenge['status'],
        }

    def get_tasks(self, auth_token: str) -> dict[str, Any]:
        self._auth(auth_token)
        return {
            'source': 'A_MASTER_BRAIN',
            'tasks': self.store.read_tasks().get('tasks', []),
        }

    def get_evidence(self, request_id: str, auth_token: str) -> dict[str, Any]:
        self._auth(auth_token)
        record = self.ledger.get(request_id)
        if record is None:
            raise LookupError('EVIDENCE_UNAVAILABLE')
        return record

    def m_a_check(self, auth_token: str) -> dict[str, Any]:
        self._auth(auth_token)
        state = self.store.read_state()
        challenge = self.store.challenge()
        return {
            'rehydration_status': challenge['status'],
            'identity': state.get('identity', {}).get('name'),
            'authority': state.get('authority'),
            'source': 'A_MASTER_BRAIN',
            'm_is_a': False,
            'checks': challenge.get('checks', {}),
        }
