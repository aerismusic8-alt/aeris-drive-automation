"""Deterministic historical OHLC backtest utilities for XM strategy research."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Mapping, Any, Callable


@dataclass(frozen=True)
class Bar:
    timestamp: int
    open: float
    high: float
    low: float
    close: float


def normalize_bars(raw: Iterable[Mapping[str, Any]]) -> list[Bar]:
    bars: list[Bar] = []
    for item in raw:
        bars.append(Bar(
            timestamp=int(item["timestamp"]),
            open=float(item["open"]),
            high=float(item["high"]),
            low=float(item["low"]),
            close=float(item["close"]),
        ))
    return sorted(bars, key=lambda b: b.timestamp)


def split_train_test(bars: list[Bar], test_ratio: float = 0.3) -> tuple[list[Bar], list[Bar]]:
    if not bars or not 0 < test_ratio < 1:
        raise ValueError("INVALID_TRAIN_TEST_SPLIT")
    cut = max(1, min(len(bars) - 1, int(len(bars) * (1 - test_ratio))))
    return bars[:cut], bars[cut:]


def run_signal_backtest(
    bars: Iterable[Bar],
    signal: Callable[[list[Bar], int], int],
) -> dict[str, Any]:
    series = list(bars)
    if len(series) < 2:
        raise ValueError("INSUFFICIENT_BARS")

    trades = 0
    wins = 0
    pnl_points = 0.0
    equity = 0.0
    peak = 0.0
    max_drawdown = 0.0

    for i in range(1, len(series)):
        side = signal(series, i)
        if side not in (-1, 0, 1):
            raise ValueError("INVALID_SIGNAL")
        if side == 0:
            continue
        entry = series[i - 1].close
        exit_price = series[i].close
        move = (exit_price - entry) * side
        pnl_points += move
        equity += move
        peak = max(peak, equity)
        max_drawdown = max(max_drawdown, peak - equity)
        trades += 1
        if move > 0:
            wins += 1

    expectancy = pnl_points / trades if trades else 0.0
    win_rate = wins / trades if trades else 0.0
    return {
        "observations": len(series),
        "trades": trades,
        "wins": wins,
        "win_rate": win_rate,
        "pnl_points": pnl_points,
        "expectancy_points": expectancy,
        "max_drawdown_points": max_drawdown,
    }
