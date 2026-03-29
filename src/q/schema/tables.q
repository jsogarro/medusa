/ Medusa — Core table definitions
/ Defines the schema for all trading system tables

\d .schema

/ Orderbook snapshots (published by Rust via Tickerplant)
orderbook:([]
    timestamp:`timestamp$();
    exchange:`symbol$();
    pair:`symbol$();
    bidPx:`float$();
    bidSz:`float$();
    askPx:`float$();
    askSz:`float$();
    depth:`int$()
    );

/ Trade events (published by Rust via Tickerplant)
trade:([]
    timestamp:`timestamp$();
    exchange:`symbol$();
    pair:`symbol$();
    price:`float$();
    quantity:`float$();
    side:`symbol$();
    tradeId:`symbol$()
    );

/ Orders placed by strategies
order:([]
    orderId:`symbol$();
    timestamp:`timestamp$();
    exchange:`symbol$();
    pair:`symbol$();
    side:`symbol$();
    orderType:`symbol$();
    price:`float$();
    quantity:`float$();
    status:`symbol$();
    strategyId:`symbol$()
    );

/ Active positions
position:([]
    exchange:`symbol$();
    pair:`symbol$();
    quantity:`float$();
    avgPrice:`float$();
    unrealizedPnl:`float$();
    strategyId:`symbol$();
    updatedAt:`timestamp$()
    );

/ Account balances per exchange
balance:([]
    exchange:`symbol$();
    currency:`symbol$();
    available:`float$();
    reserved:`float$();
    total:`float$();
    updatedAt:`timestamp$()
    );

/ Audit trail for all trade executions
auditTrade:([]
    timestamp:`timestamp$();
    orderId:`symbol$();
    exchange:`symbol$();
    pair:`symbol$();
    side:`symbol$();
    price:`float$();
    quantity:`float$();
    fee:`float$();
    feeCurrency:`symbol$();
    strategyId:`symbol$()
    );

-1 "  Schema loaded: orderbook, trade, order, position, balance, auditTrade";

\d .
