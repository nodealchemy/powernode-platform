# Classic Strategy Evaluator Audit & Remediation

**Date**: 2026-04-04
**Scope**: 7 classic (non-LLM) strategy evaluators
**Status**: All findings remediated

## Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 3 | Fixed |
| High | 5 | Fixed |
| Medium | 6 | Fixed |
| Low | 4 | Fixed/Documented |

## Critical Findings (Fixed)

### C-1. Momentum: Short position PnL ignored direction
**File**: `evaluators/momentum.rb` | **Impact**: Stop-loss fired on profitable shorts, take-profit never fired

PnL calculation used `(mid_price - entry_price) / entry_price * 100` without `* (side == "short" ? -1 : 1)`.
Momentum exit check also direction-agnostic. Whipsaw tracker inverted for shorts.

**Fix**: Added direction multiplier (matching mean_reversion.rb pattern). Fixed momentum exit to check `momentum > exit_threshold.abs` for shorts. Same fix in `check_pm_exit`.

### C-2. PredictionMarketMaking: String strength crashed settlement exit
**File**: `evaluators/prediction_market_making.rb` | **Impact**: `ArgumentError` crash during settlement proximity

`build_exit_signal` passed `strength: "strong"` — `String#clamp(0.0, 1.0)` raises TypeError.

**Fix**: Changed to `strength: 0.9`.

### C-3. Arbitrage: Cross-venue mode used random prices
**File**: `evaluators/arbitrage.rb` | **Impact**: Signals from `rand()`, not market data

`cross_venue_arbitrage` generated fake price differences. Default "parity" mode unaffected.

**Fix**: Replaced with log message stub. Awaiting real cross-venue integration via market discovery system.

## High Findings (Fixed)

### H-1. Mean Reversion: Volume gate dead (unit mismatch)
Compared 24h aggregate (huge) vs per-snapshot average (tiny). Ratio ~2880x, threshold `< 0.3` never triggers.

**Fix**: Compare recent 3-snapshot vs full lookback average (same time scale).

### H-2. MarketMaking: Inventory ratio ignored position direction
Both long+short contributed positive value. Net-flat book showed 100% utilization.

**Fix**: Net-aware calculation using `(side == "short" ? -qty : qty) * price`.

### H-4. PredictionMarketMaking: Stoikov gamma cosmetic
With defaults, inventory adjustment = 0.003 cents (5 OOM below min tick).

**Fix**: Capital-relative scaling. Default gamma raised from 0.12 to 1.0.

### H-5. TailEndYield: Cost estimation undercounted Kalshi fees
Capped at 0.5% but Kalshi $0.97 contract costs 2.1% RT.

**Fix**: Venue-aware `venue_flat_fee * 2 / mid_price` with zero-fee venue exception.

## Medium Findings (Fixed)

- **M-1**: MarketMaking skew intensity raised (0.002 → 0.01, now 0.5 cents max)
- **M-2**: Dead `fee_deduction_rate` removed from all 13 training_defaults entries
- **M-3**: Momentum median filter floor lowered for PM (0.03 → 0.005)
- **M-4**: PMM dead code no-op fixed (`has_open_position? ? signals : signals`)
- **M-5**: MarketMaking now generates ask signals without requiring existing position
- **M-6**: Evaluator param defaults aligned with training_defaults.rb (6 mismatches)

## Low Findings (Fixed/Documented)

- **L-1**: Momentum cumulative signal documented (lookback/threshold coupling)
- **L-2**: MR EMA variance — deliberate design choice, left as-is
- **L-3**: Compounding params consumed by server-side allocator, left as-is
- **L-4**: Arbitrage exit edge corrected from 0.05 to 0

## Files Modified

| File | Changes |
|------|---------|
| `evaluators/momentum.rb` | C-1, M-3, M-6, L-1 |
| `evaluators/prediction_market_making.rb` | C-2, H-4, M-4 |
| `evaluators/arbitrage.rb` | C-3, L-4 |
| `evaluators/mean_reversion.rb` | H-1, M-6 |
| `evaluators/market_making.rb` | H-2, M-1, M-5 |
| `evaluators/tail_end_yield.rb` | H-5, M-6 |
| `evaluators/longshot_fading.rb` | M-6 |
| `training_defaults.rb` | H-4, M-1, M-2 |
