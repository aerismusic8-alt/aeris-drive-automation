import unittest

from AKATH.runtime.xm_historical_backtest import (
    Bar,
    normalize_bars,
    run_signal_backtest,
    split_train_test,
)


class XmHistoricalBacktestTests(unittest.TestCase):
    def test_normalize_sorts_bars_by_timestamp(self):
        bars = normalize_bars([
            {"timestamp": 2, "open": 1, "high": 2, "low": 0, "close": 1.5},
            {"timestamp": 1, "open": 1, "high": 2, "low": 0, "close": 1.1},
        ])
        self.assertEqual([bar.timestamp for bar in bars], [1, 2])

    def test_split_train_test_is_time_ordered(self):
        bars = [Bar(i, 1, 2, 0, i + 1.0) for i in range(10)]
        train, test = split_train_test(bars, 0.3)
        self.assertEqual(len(train), 7)
        self.assertEqual(len(test), 3)
        self.assertLess(train[-1].timestamp, test[0].timestamp)

    def test_backtest_reports_positive_expectancy_for_winning_signal(self):
        bars = [Bar(i, 1, 2, 0, float(i)) for i in range(5)]
        result = run_signal_backtest(bars, lambda series, i: 1)
        self.assertEqual(result["trades"], 4)
        self.assertGreater(result["expectancy_points"], 0)
        self.assertEqual(result["win_rate"], 1.0)

    def test_backtest_rejects_invalid_signal(self):
        bars = [Bar(i, 1, 2, 0, float(i)) for i in range(3)]
        with self.assertRaisesRegex(ValueError, "INVALID_SIGNAL"):
            run_signal_backtest(bars, lambda series, i: 9)


if __name__ == "__main__":
    unittest.main()
