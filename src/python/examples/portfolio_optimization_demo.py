"""Demonstration of portfolio optimization module.

This script shows how to use the portfolio optimization tools:
- Mean-variance optimization
- Risk parity
- Black-Litterman
- Rebalancing engine
"""

from __future__ import annotations

import numpy as np
import pandas as pd

from medusa.optimization import (
    BlackLittermanOptimizer,
    MeanVarianceOptimizer,
    RebalancingEngine,
    RiskParityOptimizer,
)

# Create sample data
np.random.seed(42)

# Generate synthetic returns for 5 assets
dates = pd.date_range("2020-01-01", periods=252, freq="D")
returns = pd.DataFrame(
    {
        "AAPL": np.random.normal(0.0008, 0.02, 252),
        "MSFT": np.random.normal(0.0007, 0.018, 252),
        "GOOGL": np.random.normal(0.0009, 0.022, 252),
        "AMZN": np.random.normal(0.0010, 0.025, 252),
        "TSLA": np.random.normal(0.0012, 0.035, 252),
    },
    index=dates,
)

# Calculate expected returns and covariance (annualized)
expected_returns = returns.mean() * 252
cov_matrix = returns.cov() * 252

print("=" * 70)
print("Portfolio Optimization Demo")
print("=" * 70)
print()

# ============================================================================
# 1. Mean-Variance Optimization
# ============================================================================
print("1. Mean-Variance Optimization (Max Sharpe)")
print("-" * 70)

mv_optimizer = MeanVarianceOptimizer()
mv_result = mv_optimizer.max_sharpe(expected_returns, cov_matrix, risk_free_rate=0.04)

print(f"Expected Return: {mv_result.expected_return:.2%}")
print(f"Expected Risk:   {mv_result.expected_risk:.2%}")
print(f"Sharpe Ratio:    {mv_result.sharpe_ratio:.4f}")
print()
print("Weights:")
for asset, weight in mv_result.weights.items():
    print(f"  {asset:6s}: {weight:6.2%}")
print()

# ============================================================================
# 2. Minimum Variance Portfolio
# ============================================================================
print("2. Minimum Variance Portfolio")
print("-" * 70)

min_var_result = mv_optimizer.min_variance(cov_matrix)

print(f"Expected Risk:   {min_var_result.expected_risk:.2%}")
print()
print("Weights:")
for asset, weight in min_var_result.weights.items():
    print(f"  {asset:6s}: {weight:6.2%}")
print()

# ============================================================================
# 3. Risk Parity
# ============================================================================
print("3. Risk Parity Portfolio")
print("-" * 70)

rp_optimizer = RiskParityOptimizer()
rp_result = rp_optimizer.optimize(cov_matrix)

print(f"Expected Risk:   {rp_result.expected_risk:.2%}")
print()
print("Weights:")
for asset, weight in rp_result.weights.items():
    print(f"  {asset:6s}: {weight:6.2%}")
print()

# ============================================================================
# 4. Black-Litterman with Views
# ============================================================================
print("4. Black-Litterman with Investor Views")
print("-" * 70)

# Market caps (example)
market_caps = pd.Series(
    {
        "AAPL": 2.8e12,
        "MSFT": 2.5e12,
        "GOOGL": 1.8e12,
        "AMZN": 1.5e12,
        "TSLA": 0.8e12,
    }
)

# Investor views
views = [
    {"assets": ["AAPL"], "return": 0.15, "confidence": 0.7},  # Bullish on Apple
    {
        "assets": ["TSLA"],
        "return": 0.05,
        "confidence": 0.5,
    },  # Bearish on Tesla (lower than implied)
]

bl_optimizer = BlackLittermanOptimizer()
bl_result = bl_optimizer.optimize(
    cov_matrix, market_caps, views=views, risk_aversion=2.5, risk_free_rate=0.04
)

print(f"Expected Return: {bl_result.expected_return:.2%}")
print(f"Expected Risk:   {bl_result.expected_risk:.2%}")
print(f"Sharpe Ratio:    {bl_result.sharpe_ratio:.4f}")
print()
print("Weights:")
for asset, weight in bl_result.weights.items():
    print(f"  {asset:6s}: {weight:6.2%}")
print()

# ============================================================================
# 5. Efficient Frontier
# ============================================================================
print("5. Efficient Frontier (10 points)")
print("-" * 70)

frontier = mv_optimizer.efficient_frontier(expected_returns, cov_matrix, n_points=10)

print(f"{'Risk':<10s} {'Return':<10s} {'Sharpe':<10s}")
print("-" * 30)
for _, row in frontier.iterrows():
    print(f"{row['risk']:<10.4f} {row['return']:<10.4f} {row['sharpe']:<10.4f}")
print()

# ============================================================================
# 6. Rebalancing Engine
# ============================================================================
print("6. Rebalancing Engine")
print("-" * 70)

# Current portfolio
current_weights = pd.Series(
    {
        "AAPL": 0.30,
        "MSFT": 0.25,
        "GOOGL": 0.20,
        "AMZN": 0.15,
        "TSLA": 0.10,
    }
)

# Target portfolio (using max Sharpe weights)
target_weights = mv_result.weights

# Current prices (example)
prices = pd.Series(
    {
        "AAPL": 150.0,
        "MSFT": 300.0,
        "GOOGL": 2800.0,
        "AMZN": 3200.0,
        "TSLA": 250.0,
    }
)

rebalancer = RebalancingEngine()
trades = rebalancer.generate_trades(
    current_weights=current_weights,
    target_weights=target_weights,
    portfolio_value=100000,
    prices=prices,
    min_trade_value=100,
)

if not trades.empty:
    print("Rebalancing Trades:")
    print(
        f"{'Asset':<10s} {'Current':<10s} {'Target':<10s} {'Qty':<15s} {'Value':<15s}"
    )
    print("-" * 65)
    for _, row in trades.iterrows():
        print(
            f"{row['symbol']:<10s} "
            f"{row['current_weight']:>9.2%} "
            f"{row['target_weight']:>9.2%} "
            f"{row['trade_qty']:>14.2f} "
            f"${row['trade_value']:>13,.2f}"
        )
else:
    print("No rebalancing needed (portfolio is already at target).")

print()
print("=" * 70)
print("Demo complete!")
print("=" * 70)
