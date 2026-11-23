"""Market microstructure features for limit order book analysis."""

from __future__ import annotations

import numpy as np
import pandas as pd


def bid_ask_spread_absolute(
    bid_price: pd.Series,
    ask_price: pd.Series,
) -> pd.Series:
    """Absolute bid-ask spread.

    Args:
        bid_price: Best bid price series.
        ask_price: Best ask price series.

    Returns:
        Series with absolute spread values.
    """
    return ask_price - bid_price


def bid_ask_spread_relative(
    bid_price: pd.Series,
    ask_price: pd.Series,
) -> pd.Series:
    """Relative (percentage) bid-ask spread.

    Args:
        bid_price: Best bid price series.
        ask_price: Best ask price series.

    Returns:
        Series with relative spread as percentage of mid-price.
    """
    mid_price = (bid_price + ask_price) / 2
    absolute_spread = ask_price - bid_price
    return (absolute_spread / mid_price.replace(0, np.nan)) * 100


def orderbook_depth(
    bid_sizes: pd.DataFrame,
    ask_sizes: pd.DataFrame,
    levels: int = 5,
) -> pd.DataFrame:
    """Total liquidity depth at N levels of the order book.

    Args:
        bid_sizes: DataFrame with columns ['bid_size_1', 'bid_size_2', ...].
        ask_sizes: DataFrame with columns ['ask_size_1', 'ask_size_2', ...].
        levels: Number of levels to sum.

    Returns:
        DataFrame with columns: total_bid_depth, total_ask_depth, depth_imbalance.
    """
    bid_cols = [f"bid_size_{i + 1}" for i in range(levels)]
    ask_cols = [f"ask_size_{i + 1}" for i in range(levels)]

    total_bid = bid_sizes[bid_cols].sum(axis=1)
    total_ask = ask_sizes[ask_cols].sum(axis=1)

    # Depth imbalance (positive = more bids, negative = more asks)
    imbalance = (total_bid - total_ask) / (total_bid + total_ask).replace(0, np.nan)

    return pd.DataFrame(
        {
            "total_bid_depth": total_bid,
            "total_ask_depth": total_ask,
            "depth_imbalance": imbalance,
        }
    )


def mid_price_volatility(
    bid_price: pd.Series,
    ask_price: pd.Series,
    window: int = 20,
) -> pd.Series:
    """Realized volatility of mid-price over rolling window.

    Args:
        bid_price: Best bid price series.
        ask_price: Best ask price series.
        window: Rolling window size.

    Returns:
        Series with rolling volatility of mid-price.
    """
    mid_price = (bid_price + ask_price) / 2
    returns = mid_price.pct_change()
    return returns.rolling(window).std() * np.sqrt(window)


def trade_arrival_rate(
    trade_timestamps: pd.Series,
    window: int = 60,
) -> pd.Series:
    """Poisson intensity (trade arrival rate) over rolling window.

    Args:
        trade_timestamps: Series of trade timestamps (datetime index).
        window: Rolling window size in seconds.

    Returns:
        Series with trades per second (Poisson lambda).
    """
    # Resample to 1-second bins
    counts = trade_timestamps.resample("1s").count()

    # Rolling mean over window
    arrival_rate = counts.rolling(f"{window}s").mean()

    return arrival_rate


def effective_spread(
    price: pd.Series,
    mid_price: pd.Series,
) -> pd.Series:
    """Effective spread: 2 * |trade_price - mid_price|.

    Measures actual cost of execution vs mid-price.

    Args:
        price: Executed trade price.
        mid_price: Mid-price at trade time.

    Returns:
        Series with effective spread values.
    """
    return 2 * (price - mid_price).abs()


def realized_spread(
    price: pd.Series,
    mid_price: pd.Series,
    lag: int = 5,
) -> pd.Series:
    """Realized spread: (trade_price - mid_price_future) * direction.

    Measures temporary vs permanent price impact.

    Args:
        price: Executed trade price.
        mid_price: Mid-price at trade time.
        lag: Future lag for mid-price comparison (default 5 ticks).

    Returns:
        Series with realized spread values.
    """
    # Shift mid-price forward by lag to get future mid-price
    mid_price_future = mid_price.shift(-lag)

    # Realized spread = 2 * (trade_price - mid_price_future)
    # Positive when trade price moves toward future mid (liquidity provision)
    return 2 * (price - mid_price_future)


def price_impact(
    trade_price: pd.Series,
    mid_price_before: pd.Series,
    mid_price_after: pd.Series,
) -> pd.Series:
    """Price impact: change in mid-price after trade execution.

    Args:
        trade_price: Executed trade price.
        mid_price_before: Mid-price before trade.
        mid_price_after: Mid-price after trade (e.g., next tick).

    Returns:
        Series with price impact values (positive = moved mid up).
    """
    return mid_price_after - mid_price_before


def roll_measure(
    prices: pd.Series,
    window: int = 20,
) -> pd.Series:
    """Roll measure of bid-ask spread from trade prices.

    Estimates spread from serial covariance of price changes.

    Args:
        prices: Trade price series.
        window: Rolling window size.

    Returns:
        Series with estimated spread values.

    Note:
        Roll (1984): spread ≈ 2 * sqrt(-Cov(ΔP_t, ΔP_{t-1}))
    """
    price_changes = prices.diff()
    serial_cov = price_changes.rolling(window).apply(
        lambda x: np.cov(x[:-1], x[1:])[0, 1] if len(x) > 1 else np.nan, raw=False
    )

    # Spread = 2 * sqrt(-covariance), clamped at 0
    spread = 2 * np.sqrt(np.maximum(-serial_cov, 0))
    return spread


def add_microstructure_features(
    df: pd.DataFrame,
    has_orderbook: bool = False,
) -> pd.DataFrame:
    """Add market microstructure features to a trade/quote DataFrame.

    Args:
        df: DataFrame with 'bid_price', 'ask_price' at minimum.
            Optionally: 'bid_size_1', 'ask_size_1', etc. for orderbook depth.
        has_orderbook: Whether orderbook depth columns are present.

    Returns:
        DataFrame with microstructure features appended.
    """
    result = df.copy()

    # Bid-ask spread (requires bid/ask columns)
    if "bid_price" in df.columns and "ask_price" in df.columns:
        result["spread_abs"] = bid_ask_spread_absolute(df["bid_price"], df["ask_price"])
        result["spread_rel"] = bid_ask_spread_relative(df["bid_price"], df["ask_price"])
        result["mid_volatility"] = mid_price_volatility(df["bid_price"], df["ask_price"], window=20)

    # Orderbook depth (if available)
    if has_orderbook and "bid_size_1" in df.columns and "ask_size_1" in df.columns:
        depth_df = orderbook_depth(df, df, levels=5)
        result = pd.concat([result, depth_df], axis=1)

    # Roll spread estimate (from trade prices)
    if "close" in df.columns:
        result["roll_spread"] = roll_measure(df["close"], window=20)

    return result
