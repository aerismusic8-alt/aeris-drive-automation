from __future__ import annotations

import json
import os
import threading
from pathlib import Path
from typing import Any

class GatewayInputQueue:
    """Durable transport inbox; never treated as execution evidence."""
    def __init__(self, root: str | Path):
        self.root=Path(root); self.root.mkdir(parents=True,exist_ok=True); self._lock=threading.Lock()

    def put(self, record: dict[str, Any]) -> None:
        request_id=str(record['request_id']); key=str(record.get('idempotency_key') or ''); target=self.root/f'{request_id}.json'; tmp=target.with_suffix('.json.tmp')
        with self._lock:
            if key:
                existing=self.find_by_idempotency_key(key)
                if existing is not None and existing.get('request_id') != request_id: raise ValueError('DUPLICATE_IDEMPOTENCY_KEY')
            if target.exists():
                existing=json.loads(target.read_text(encoding='utf-8'))
                if existing != record: raise ValueError('REQUEST_ID_CONFLICT')
                return
            tmp.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8'); os.replace(tmp,target)

    def get(self, request_id: str) -> dict[str, Any] | None:
        target=self.root/f'{request_id}.json'
        if not target.exists(): return None
        try: return json.loads(target.read_text(encoding='utf-8'))
        except (OSError,json.JSONDecodeError): return None

    def find_by_idempotency_key(self, key: str) -> dict[str, Any] | None:
        if not key: return None
        for target in self.root.glob('*.json'):
            try: record=json.loads(target.read_text(encoding='utf-8'))
            except (OSError,json.JSONDecodeError): continue
            if record.get('idempotency_key')==key: return record
        return None
