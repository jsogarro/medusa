"""Alpaca paper trading client for strategy validation."""

from __future__ import annotations

import os
from datetime import datetime
from typing import Any

import pandas as pd
from loguru import logger

try:
    from alpaca.trading import TradingClient
    from alpaca.trading.enums import OrderSide, TimeInForce
    from alpaca.trading.requests import (
        GetOrdersRequest,
        GetPortfolioHistoryRequest,
        MarketOrderRequest,
    )

    ALPACA_TRADING_AVAILABLE = True
except ImportError:
    ALPACA_TRADING_AVAILABLE = False
    logger.warning("alpaca-py trading module not installed - AlpacaPaperClient unavailable")


def _normalize_side(side: str) -> str:
    side = side.lower()
    if side not in ("buy", "sell"):
        raise ValueError(f"Unsupported side: {side!r}. Use 'buy' or 'sell'")
    return side


# Alpaca's period tokens are number + D/W/M/A (A = year); "1Y" is accepted as an alias.
_PERIODS = ("1D", "1W", "1M", "3M", "1Y", "1A")


def _normalize_period(period: str) -> str:
    if period not in _PERIODS:
        raise ValueError(f"Unsupported period: {period!r}. Use one of: {list(_PERIODS)}")
    return period


class AlpacaPaperClient:
    """Alpaca paper trading client for strategy validation."""

    def __init__(self, api_key: str | None = None, secret_key: str | None = None) -> None:
        """Initialize Alpaca paper trading client.

        Args:
            api_key: Alpaca API key (defaults to ALPACA_API_KEY env var)
            secret_key: Alpaca secret key (defaults to ALPACA_SECRET_KEY env var)

        Raises:
            ImportError: If alpaca-py is not installed
            ValueError: If API keys are not provided and not in environment
        """
        if not ALPACA_TRADING_AVAILABLE:
            raise ImportError(
                "alpaca-py trading module not installed. Install with: pip install alpaca-py"
            )

        self.api_key = api_key or os.getenv("ALPACA_API_KEY")
        self.secret_key = secret_key or os.getenv("ALPACA_SECRET_KEY")

        if not self.api_key or not self.secret_key:
            raise ValueError(
                "Alpaca API keys not found. Set ALPACA_API_KEY and ALPACA_SECRET_KEY "
                "environment variables or pass them to constructor."
            )

        # Initialize trading client (paper=True for paper trading)
        self.client = TradingClient(
            api_key=self.api_key,
            secret_key=self.secret_key,
            paper=True,
        )
        logger.info("Alpaca paper trading client initialized")

    def submit_order(
        self,
        symbol: str,
        qty: float,
        side: str,
        order_type: str = "market",
        time_in_force: str = "day",
        limit_price: float | None = None,
    ) -> dict[str, Any]:
        """Submit an order to Alpaca paper trading.

        Args:
            symbol: Stock symbol (e.g., "AAPL")
            qty: Quantity (number of shares)
            side: Order side ("buy" or "sell")
            order_type: Order type ("market" or "limit")
            time_in_force: Time in force ("day", "gtc", "ioc", "fok")
            limit_price: Limit price (required for limit orders)

        Returns:
            Dictionary with order details (id, status, filled_qty, etc.)
        """
        # Map strings to enums
        side_enum = OrderSide.BUY if _normalize_side(side) == "buy" else OrderSide.SELL
        tif_map = {
            "day": TimeInForce.DAY,
            "gtc": TimeInForce.GTC,
            "ioc": TimeInForce.IOC,
            "fok": TimeInForce.FOK,
        }
        tif_enum = tif_map.get(time_in_force.lower(), TimeInForce.DAY)

        # Create order request
        if order_type.lower() == "market":
            request = MarketOrderRequest(
                symbol=symbol,
                qty=qty,
                side=side_enum,
                time_in_force=tif_enum,
            )
        elif order_type.lower() == "limit":
            if limit_price is None:
                raise ValueError("limit_price required for limit orders")
            from alpaca.trading.requests import LimitOrderRequest

            request = LimitOrderRequest(
                symbol=symbol,
                qty=qty,
                side=side_enum,
                time_in_force=tif_enum,
                limit_price=limit_price,
            )
        else:
            raise ValueError(f"Unsupported order_type: {order_type}")

        # Submit order
        order = self.client.submit_order(request)

        # Convert to dict
        order_dict = {
            "id": str(order.id),
            "client_order_id": order.client_order_id,
            "symbol": order.symbol,
            "qty": float(order.qty) if order.qty else 0.0,
            "filled_qty": float(order.filled_qty) if order.filled_qty else 0.0,
            "side": order.side.value if order.side else None,
            "order_type": order.order_type.value if order.order_type else None,
            "status": order.status.value if order.status else None,
            "created_at": order.created_at.isoformat() if order.created_at else None,
            "filled_at": order.filled_at.isoformat() if order.filled_at else None,
            "filled_avg_price": (float(order.filled_avg_price) if order.filled_avg_price else None),
        }

        logger.info(
            f"Submitted {side} order for {qty} {symbol} "
            f"(order_id={order_dict['id']}, status={order_dict['status']})"
        )
        return order_dict

    def cancel_order(self, order_id: str) -> bool:
        """Cancel an open order.

        Args:
            order_id: Order ID to cancel

        Returns:
            True if cancelled successfully
        """
        try:
            self.client.cancel_order_by_id(order_id)
            logger.info(f"Cancelled order {order_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to cancel order {order_id}: {e}")
            return False

    def get_positions(self) -> list[dict[str, Any]]:
        """Get all open positions.

        Returns:
            List of position dictionaries
        """
        positions = self.client.get_all_positions()

        position_list = []
        for pos in positions:
            position_list.append(
                {
                    "symbol": pos.symbol,
                    "qty": float(pos.qty) if pos.qty else 0.0,
                    "side": "long" if float(pos.qty or 0) > 0 else "short",
                    "avg_entry_price": float(pos.avg_entry_price) if pos.avg_entry_price else 0.0,
                    "market_value": float(pos.market_value) if pos.market_value else 0.0,
                    "cost_basis": float(pos.cost_basis) if pos.cost_basis else 0.0,
                    "unrealized_pl": (float(pos.unrealized_pl) if pos.unrealized_pl else 0.0),
                    "unrealized_plpc": (float(pos.unrealized_plpc) if pos.unrealized_plpc else 0.0),
                    "current_price": float(pos.current_price) if pos.current_price else 0.0,
                }
            )

        logger.info(f"Retrieved {len(position_list)} positions")
        return position_list

    def get_account(self) -> dict[str, Any]:
        """Get account information.

        Returns:
            Dictionary with account details (equity, cash, buying_power, etc.)
        """
        account = self.client.get_account()

        account_dict = {
            "id": account.id,
            "status": account.status.value if account.status else None,
            "currency": account.currency,
            "cash": float(account.cash) if account.cash else 0.0,
            "portfolio_value": (float(account.portfolio_value) if account.portfolio_value else 0.0),
            "equity": float(account.equity) if account.equity else 0.0,
            "last_equity": float(account.last_equity) if account.last_equity else 0.0,
            "buying_power": float(account.buying_power) if account.buying_power else 0.0,
            "initial_margin": (float(account.initial_margin) if account.initial_margin else 0.0),
            "maintenance_margin": (
                float(account.maintenance_margin) if account.maintenance_margin else 0.0
            ),
            "daytrade_count": account.daytrade_count,
            "daytrading_buying_power": (
                float(account.daytrading_buying_power) if account.daytrading_buying_power else 0.0
            ),
        }

        logger.info(f"Account equity: ${account_dict['equity']:.2f}")
        return account_dict

    def get_portfolio_history(
        self,
        period: str = "1M",
        timeframe: str = "1D",
    ) -> pd.DataFrame:
        """Get portfolio equity history.

        Args:
            period: Time period ("1D", "1W", "1M", "3M", "1Y" or "1A")
            timeframe: Sampling interval ("1Min", "5Min", "15Min", "1H", "1D")

        Returns:
            DataFrame with columns: timestamp, equity, profit_loss, profit_loss_pct
        """
        token = _normalize_period(period).replace("1Y", "1A")
        history = self.client.get_portfolio_history(
            history_filter=GetPortfolioHistoryRequest(period=token, timeframe=timeframe)
        )

        # Convert to DataFrame
        df = pd.DataFrame(
            {
                "timestamp": [datetime.fromtimestamp(ts) for ts in history.timestamp],
                "equity": history.equity,
                "profit_loss": history.profit_loss,
                "profit_loss_pct": history.profit_loss_pct,
            }
        )

        df = df.set_index("timestamp")

        logger.info(f"Retrieved portfolio history ({period}, {len(df)} points)")
        return df

    def get_orders(
        self,
        status: str | None = None,
        limit: int = 100,
    ) -> list[dict[str, Any]]:
        """Get orders (optionally filtered by status).

        Args:
            status: Filter by status ("open", "closed", "all")
            limit: Maximum number of orders to return

        Returns:
            List of order dictionaries
        """
        from alpaca.trading.enums import QueryOrderStatus

        status_map = {
            "open": QueryOrderStatus.OPEN,
            "closed": QueryOrderStatus.CLOSED,
            "all": QueryOrderStatus.ALL,
        }

        status_enum = (
            status_map.get(status, QueryOrderStatus.ALL) if status else QueryOrderStatus.ALL
        )

        request = GetOrdersRequest(
            status=status_enum,
            limit=limit,
        )

        orders = self.client.get_orders(request)

        order_list = []
        for order in orders:
            order_list.append(
                {
                    "id": str(order.id),
                    "symbol": order.symbol,
                    "qty": float(order.qty) if order.qty else 0.0,
                    "filled_qty": float(order.filled_qty) if order.filled_qty else 0.0,
                    "side": order.side.value if order.side else None,
                    "order_type": order.order_type.value if order.order_type else None,
                    "status": order.status.value if order.status else None,
                    "created_at": order.created_at.isoformat() if order.created_at else None,
                    "filled_at": order.filled_at.isoformat() if order.filled_at else None,
                }
            )

        logger.info(f"Retrieved {len(order_list)} orders")
        return order_list
