"""Portfolio optimization: mean-variance, risk parity, Black-Litterman, CVaR minimization.

This module provides comprehensive portfolio optimization tools:

- MeanVarianceOptimizer: Markowitz optimization with constraints
- RiskParityOptimizer: Equal risk contribution portfolios
- BlackLittermanOptimizer: Bayesian views integration
- RebalancingEngine: Trade list generation

Example:
    >>> from medusa.optimization import MeanVarianceOptimizer
    >>> optimizer = MeanVarianceOptimizer()
    >>> result = optimizer.max_sharpe(expected_returns, cov_matrix)
    >>> print(result.weights)

"""

from medusa.optimization.portfolio_optimizer import (
    BlackLittermanOptimizer,
    MeanVarianceOptimizer,
    OptimizationResult,
    RebalancingEngine,
    RiskParityOptimizer,
)

__all__ = [
    "OptimizationResult",
    "MeanVarianceOptimizer",
    "RiskParityOptimizer",
    "BlackLittermanOptimizer",
    "RebalancingEngine",
]
