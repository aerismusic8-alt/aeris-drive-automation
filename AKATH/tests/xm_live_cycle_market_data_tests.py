import unittest
from datetime import datetime, timezone

from AKATH.runtime.xm_live_cycle import fetch_market_data, normalize_market_data, market_context


class XmLiveCycleMarketDataTests(unittest.TestCase):
    def test_fetch_market_data_reads_market_endpoint(self):
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self):
                return b'{"ok":true,"market_data":{"account_scope":"XM_MICRO_K_DESIGNATED_ACCOUNT","received_at":"2026-09-08T00:00:00Z","snapshots":[{"symbol":"XAUUSD","timeframe":"M5","bars":[{"timestamp":1,"open":1,"high":2,"low":0,"close":1.5}],"source":"MT5_COPYRATES","read_only":true}]}}'

        def opener(request, timeout=20):
            self.assertTrue(request.full_url.endswith('/xm/market-data'))
            self.assertEqual(timeout, 20)
            return Response()

        payload = fetch_market_data('https://example.invalid/runtime', opener=opener)
        self.assertTrue(payload['ok'])
        self.assertEqual(payload['market_data']['snapshots'][0]['symbol'], 'XAUUSD')

    def test_normalize_market_data_extracts_latest_snapshot(self):
        raw = {
            'ok': True,
            'market_data': {
                'account_scope': 'XM_MICRO_K_DESIGNATED_ACCOUNT',
                'received_at': '2026-09-08T00:00:00Z',
                'snapshots': [
                    {'symbol':'XAUUSD','timeframe':'M5','bars':[{'timestamp':2,'close':2.0},{'timestamp':1,'close':1.0}], 'source':'MT5_COPYRATES','read_only':True}
                ]
            }
        }
        result = normalize_market_data(raw)
        self.assertTrue(result['available'])
        self.assertEqual(result['bars_count'], 2)
        self.assertEqual(result['latest_timestamp'], 2)
        self.assertEqual(result['symbol'], 'XAUUSD')

    def test_market_context_rejects_missing_or_stale_market_data(self):
        stale = {'market_data': {'received_at': '2026-09-07T00:00:00Z','snapshots':[]}}
        result = market_context(stale, now=datetime(2026,9,8,tzinfo=timezone.utc), max_age_sec=300)
        self.assertFalse(result['usable'])
        self.assertEqual(result['reason'], 'MARKET_DATA_STALE')


if __name__ == '__main__':
    unittest.main()
