//! Unit tests for gds-trade-subscriber
//!
//! Tests cover deduplication, exchange adapter parsing, and trade normalization.

#[cfg(test)]
mod deduplicator_tests {
    use crate::deduplicator::TradeDeduplicator;

    #[test]
    fn test_insert_new_trade() {
        let mut dedup = TradeDeduplicator::new(100);
        assert!(!dedup.is_duplicate("trade1"));
        dedup.record("trade1");
        assert!(dedup.is_duplicate("trade1"));
        assert_eq!(dedup.len(), 1);
    }

    #[test]
    fn test_duplicate_detection() {
        let mut dedup = TradeDeduplicator::new(100);
        dedup.record("trade1");
        dedup.record("trade2");
        dedup.record("trade3");

        assert!(dedup.is_duplicate("trade1"));
        assert!(dedup.is_duplicate("trade2"));
        assert!(dedup.is_duplicate("trade3"));
        assert!(!dedup.is_duplicate("trade4"));
        assert_eq!(dedup.len(), 3);
    }

    #[test]
    fn test_eviction_at_capacity() {
        let mut dedup = TradeDeduplicator::new(3);
        dedup.record("trade1");
        dedup.record("trade2");
        dedup.record("trade3");

        assert_eq!(dedup.len(), 3);
        assert!(dedup.is_duplicate("trade1"));
        assert!(dedup.is_duplicate("trade2"));
        assert!(dedup.is_duplicate("trade3"));

        // Add 4th trade, should evict trade1 (oldest)
        dedup.record("trade4");
        assert_eq!(dedup.len(), 3);
        assert!(!dedup.is_duplicate("trade1")); // evicted
        assert!(dedup.is_duplicate("trade2"));
        assert!(dedup.is_duplicate("trade3"));
        assert!(dedup.is_duplicate("trade4"));
    }

    #[test]
    fn test_eviction_order() {
        let mut dedup = TradeDeduplicator::new(2);
        dedup.record("first");
        dedup.record("second");

        // Add third, evicts first
        dedup.record("third");
        assert!(!dedup.is_duplicate("first"));
        assert!(dedup.is_duplicate("second"));
        assert!(dedup.is_duplicate("third"));

        // Add fourth, evicts second
        dedup.record("fourth");
        assert!(!dedup.is_duplicate("first"));
        assert!(!dedup.is_duplicate("second"));
        assert!(dedup.is_duplicate("third"));
        assert!(dedup.is_duplicate("fourth"));
    }

    #[test]
    fn test_clear() {
        let mut dedup = TradeDeduplicator::new(100);
        dedup.record("trade1");
        dedup.record("trade2");
        assert_eq!(dedup.len(), 2);

        dedup.clear();
        assert_eq!(dedup.len(), 0);
        assert!(dedup.is_empty());
        assert!(!dedup.is_duplicate("trade1"));
        assert!(!dedup.is_duplicate("trade2"));
    }
}

#[cfg(test)]
mod exchange_adapter_tests {
    use crate::exchange_adapter::{
        BitstampTradeAdapter, CoinbaseTradeAdapter, KrakenTradeAdapter, TradeAdapter,
    };
    use exchange_connector::types::Side;

    #[test]
    fn test_bitstamp_subscribe_message() {
        let adapter = BitstampTradeAdapter::new("http://test".to_string());
        let msg = adapter.build_subscribe_message(&["btcusd".to_string(), "ethusd".to_string()]);
        assert!(msg.contains("live_trades_btcusd"));
        assert!(msg.contains("live_trades_ethusd"));
        assert!(msg.contains("bts:subscribe"));
    }

    #[test]
    fn test_bitstamp_parse_trade_message() {
        let adapter = BitstampTradeAdapter::new("http://test".to_string());
        let json = r#"{"event":"trade","channel":"live_trades_btcusd","data":{"id":123456,"amount":0.5,"price":50000.0,"type":0,"timestamp":"1640000000"}}"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);

        let trade = &trades[0];
        assert_eq!(trade.exchange, "bitstamp");
        assert_eq!(trade.symbol, "BTCUSD");
        assert_eq!(trade.trade_id, "123456");
        assert_eq!(trade.price, 50000.0);
        assert_eq!(trade.quantity, 0.5);
        assert_eq!(trade.side, Side::Buy);
    }

    #[test]
    fn test_bitstamp_parse_sell_trade() {
        let adapter = BitstampTradeAdapter::new("http://test".to_string());
        let json = r#"{"event":"trade","channel":"live_trades_ethusd","data":{"id":789,"amount":1.2,"price":3000.0,"type":1,"timestamp":"1640000000"}}"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].side, Side::Sell);
        assert_eq!(trades[0].symbol, "ETHUSD");
    }

    #[test]
    fn test_coinbase_subscribe_message() {
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());
        let msg = adapter.build_subscribe_message(&["BTC-USD".to_string(), "ETH-USD".to_string()]);
        assert!(msg.contains("matches"));
        assert!(msg.contains("BTC-USD"));
        assert!(msg.contains("ETH-USD"));
    }

    #[test]
    fn test_coinbase_parse_trade_message() {
        std::env::remove_var("COINBASE_USE_ADVANCED_TRADE"); // Ensure legacy mode
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());
        let json = r#"{"type":"match","trade_id":123,"price":"50000.00","size":"0.5","side":"buy","time":"2024-01-01T00:00:00.000000Z","product_id":"BTC-USD"}"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);

        let trade = &trades[0];
        assert_eq!(trade.exchange, "coinbase");
        assert_eq!(trade.symbol, "BTC-USD");
        assert_eq!(trade.trade_id, "123");
        assert_eq!(trade.price, 50000.0);
        assert_eq!(trade.quantity, 0.5);
        assert_eq!(trade.side, Side::Buy);
    }

    #[test]
    fn test_coinbase_parse_sell_trade() {
        std::env::remove_var("COINBASE_USE_ADVANCED_TRADE"); // Ensure legacy mode
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());
        let json = r#"{"type":"match","trade_id":456,"price":"3000.50","size":"2.0","side":"sell","time":"2024-01-01T00:00:00Z","product_id":"ETH-USD"}"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].side, Side::Sell);
        assert_eq!(trades[0].price, 3000.5);
    }

    #[test]
    fn test_kraken_subscribe_message() {
        let adapter = KrakenTradeAdapter::new("http://test".to_string());
        let msg = adapter.build_subscribe_message(&["XBT/USD".to_string(), "ETH/USD".to_string()]);
        assert!(msg.contains("subscribe"));
        assert!(msg.contains("trade"));
        assert!(msg.contains("XBT/USD"));
        assert!(msg.contains("ETH/USD"));
    }

    #[test]
    fn test_kraken_parse_trade_message() {
        let adapter = KrakenTradeAdapter::new("http://test".to_string());
        // Kraken v2 format: JSON object with channel, data array
        let json = r#"{
            "channel": "trade",
            "data": [
                {
                    "symbol": "BTC/USD",
                    "price": 50000.0,
                    "qty": 0.5,
                    "side": "buy",
                    "timestamp": "2024-01-01T00:00:00.000000Z",
                    "trade_id": 12345
                }
            ]
        }"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);

        let trade = &trades[0];
        assert_eq!(trade.exchange, "kraken");
        assert_eq!(trade.symbol, "BTC/USD");
        assert_eq!(trade.price, 50000.0);
        assert_eq!(trade.quantity, 0.5);
        assert_eq!(trade.side, Side::Buy);
    }

    #[test]
    fn test_kraken_parse_sell_trade() {
        let adapter = KrakenTradeAdapter::new("http://test".to_string());
        let json = r#"{
            "channel": "trade",
            "data": [
                {
                    "symbol": "ETH/USD",
                    "price": 3000.50,
                    "qty": 1.2,
                    "side": "sell",
                    "timestamp": "2024-01-01T00:00:01.000000Z",
                    "trade_id": 12346
                }
            ]
        }"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].side, Side::Sell);
        assert_eq!(trades[0].symbol, "ETH/USD");
    }

    #[test]
    fn test_normalized_trade_conversion() {
        use crate::exchange_adapter::NormalizedTrade;
        use chrono::Utc;

        let normalized = NormalizedTrade {
            exchange: "test".to_string(),
            symbol: "BTC-USD".to_string(),
            trade_id: "123".to_string(),
            price: 50000.0,
            quantity: 0.5,
            side: Side::Buy,
            timestamp: Utc::now(),
        };

        let trade = normalized.clone().into_trade();
        assert_eq!(trade.exchange, "test");
        assert_eq!(trade.pair, "BTC-USD");
        assert_eq!(trade.id, "123");
        assert_eq!(trade.price, 50000.0);
        assert_eq!(trade.quantity, 0.5);
        assert_eq!(trade.side, Side::Buy);
        assert!(trade.is_maker.is_none());
    }

    #[test]
    fn test_non_trade_messages_ignored() {
        let adapter = BitstampTradeAdapter::new("http://test".to_string());
        // Subscription confirmation doesn't have the same structure, so it will fail to parse
        // That's expected - we just want to verify non-trade events return empty vec
        let json = r#"{"event":"heartbeat","channel":"","data":{}}"#;

        // This might error during parsing, which is fine - we're testing that non-trade events
        // either return empty vec or error (both acceptable)
        if let Ok(trades) = adapter.parse_message(json) {
            assert_eq!(trades.len(), 0);
        }
    }

    #[test]
    fn test_coinbase_non_trade_messages_ignored() {
        // Ensure we're in legacy mode for this test
        std::env::remove_var("COINBASE_USE_ADVANCED_TRADE");
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());
        let json =
            r#"{"type":"subscriptions","channels":[{"name":"matches","product_ids":["BTC-USD"]}]}"#;

        // Legacy mode expects different format, so this will return empty
        if let Ok(trades) = adapter.parse_message(json) {
            assert_eq!(trades.len(), 0); // Not a match event
        }
        // If it errors, that's also acceptable for non-trade messages
    }

    // === Additional Binance Trade Tests ===

    #[test]
    fn test_binance_trade_parse() {
        use crate::exchange_adapter::BinanceTradeAdapter;
        let adapter = BinanceTradeAdapter::new("http://test".to_string());
        let json = r#"{
            "e": "trade",
            "E": 1640000000123,
            "s": "BTCUSDT",
            "t": 12345,
            "p": "67000.00",
            "q": "0.1",
            "T": 1640000000000,
            "m": false
        }"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);

        let trade = &trades[0];
        assert_eq!(trade.exchange, "binance");
        assert_eq!(trade.symbol, "BTC/USD");
        assert_eq!(trade.trade_id, "12345");
        assert_eq!(trade.price, 67000.00);
        assert_eq!(trade.quantity, 0.1);
        assert_eq!(trade.side, Side::Buy); // m=false means taker is buyer
    }

    #[test]
    fn test_binance_trade_sell_side() {
        use crate::exchange_adapter::BinanceTradeAdapter;
        let adapter = BinanceTradeAdapter::new("http://test".to_string());
        let json = r#"{
            "e": "trade",
            "E": 1640000000123,
            "s": "ETHUSDT",
            "t": 67890,
            "p": "3500.50",
            "q": "2.5",
            "T": 1640000000000,
            "m": true
        }"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);
        assert_eq!(trades[0].side, Side::Sell); // m=true means taker is seller
    }

    // === Coinbase Advanced Trade Tests ===

    #[test]
    fn test_coinbase_advanced_trade() {
        // Enable Advanced Trade mode for this test
        std::env::set_var("COINBASE_USE_ADVANCED_TRADE", "true");
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());

        // Correct Coinbase Advanced Trade format with channel and events
        let json = r#"{"channel":"market_trades","events":[{"trades":[{"trade_id":"123","product_id":"BTC-USD","price":"67000.00","size":"0.5","side":"BUY","time":"2024-01-01T00:00:00.000000Z"}]}]}"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);

        let trade = &trades[0];
        assert_eq!(trade.exchange, "coinbase");
        assert_eq!(trade.symbol, "BTC-USD");
        assert_eq!(trade.price, 67000.0);
        assert_eq!(trade.side, Side::Buy);

        std::env::remove_var("COINBASE_USE_ADVANCED_TRADE");
    }

    #[test]
    fn test_coinbase_advanced_multiple_trades() {
        std::env::set_var("COINBASE_USE_ADVANCED_TRADE", "true");
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());

        // Multiple trades in single event
        let json = r#"{"channel":"market_trades","events":[{"trades":[{"trade_id":"1","product_id":"BTC-USD","price":"67000.00","size":"0.5","side":"BUY","time":"2024-01-01T00:00:00Z"},{"trade_id":"2","product_id":"BTC-USD","price":"67001.00","size":"0.3","side":"SELL","time":"2024-01-01T00:00:01Z"}]}]}"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 2);
        assert_eq!(trades[0].side, Side::Buy);
        assert_eq!(trades[1].side, Side::Sell);

        std::env::remove_var("COINBASE_USE_ADVANCED_TRADE");
    }

    // === Kraken v2 Trade Tests ===

    #[test]
    fn test_kraken_v2_trade_format() {
        let adapter = KrakenTradeAdapter::new("http://test".to_string());
        let json = r#"{
            "channel": "trade",
            "type": "update",
            "data": [
                {
                    "symbol": "BTC/USD",
                    "price": 67000.50,
                    "qty": 0.75,
                    "side": "buy",
                    "timestamp": "2024-01-01T12:00:00.123456Z",
                    "trade_id": 99999
                }
            ]
        }"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 1);

        let trade = &trades[0];
        assert_eq!(trade.exchange, "kraken");
        assert_eq!(trade.symbol, "BTC/USD");
        assert_eq!(trade.price, 67000.50);
        assert_eq!(trade.quantity, 0.75);
        assert_eq!(trade.side, Side::Buy);
    }

    #[test]
    fn test_kraken_v2_multiple_trades() {
        let adapter = KrakenTradeAdapter::new("http://test".to_string());
        let json = r#"{
            "channel": "trade",
            "type": "update",
            "data": [
                {
                    "symbol": "ETH/USD",
                    "price": 3500.00,
                    "qty": 1.0,
                    "side": "buy",
                    "timestamp": "2024-01-01T12:00:00Z",
                    "trade_id": 100001
                },
                {
                    "symbol": "ETH/USD",
                    "price": 3501.00,
                    "qty": 0.5,
                    "side": "sell",
                    "timestamp": "2024-01-01T12:00:01Z",
                    "trade_id": 100002
                }
            ]
        }"#;

        let trades = adapter.parse_message(json).unwrap();
        assert_eq!(trades.len(), 2);
        assert_eq!(trades[0].side, Side::Buy);
        assert_eq!(trades[1].side, Side::Sell);
    }

    // === Side Detection Tests ===

    #[test]
    fn test_side_detection_bitstamp() {
        let adapter = BitstampTradeAdapter::new("http://test".to_string());

        // type=0 is Buy
        let buy_json = r#"{"event":"trade","channel":"live_trades_btcusd","data":{"id":1,"amount":1.0,"price":50000.0,"type":0,"timestamp":"1640000000"}}"#;
        let trades = adapter.parse_message(buy_json).unwrap();
        assert_eq!(trades[0].side, Side::Buy);

        // type=1 is Sell
        let sell_json = r#"{"event":"trade","channel":"live_trades_btcusd","data":{"id":2,"amount":1.0,"price":50000.0,"type":1,"timestamp":"1640000000"}}"#;
        let trades = adapter.parse_message(sell_json).unwrap();
        assert_eq!(trades[0].side, Side::Sell);
    }

    #[test]
    fn test_side_detection_coinbase() {
        std::env::remove_var("COINBASE_USE_ADVANCED_TRADE"); // Ensure legacy mode
        let adapter = CoinbaseTradeAdapter::new("http://test".to_string());

        // side="buy"
        let buy_json = r#"{"type":"match","trade_id":1,"price":"50000.00","size":"1.0","side":"buy","time":"2024-01-01T00:00:00Z","product_id":"BTC-USD"}"#;
        let trades = adapter.parse_message(buy_json).unwrap();
        assert_eq!(trades[0].side, Side::Buy);

        // side="sell"
        let sell_json = r#"{"type":"match","trade_id":2,"price":"50000.00","size":"1.0","side":"sell","time":"2024-01-01T00:00:00Z","product_id":"BTC-USD"}"#;
        let trades = adapter.parse_message(sell_json).unwrap();
        assert_eq!(trades[0].side, Side::Sell);
    }

    #[test]
    fn test_side_detection_binance() {
        use crate::exchange_adapter::BinanceTradeAdapter;
        let adapter = BinanceTradeAdapter::new("http://test".to_string());

        // m=false means taker is buyer → Buy
        let buy_json = r#"{"e":"trade","E":1640000000000,"s":"BTCUSDT","t":1,"p":"50000.00","q":"1.0","T":1640000000000,"m":false}"#;
        let trades = adapter.parse_message(buy_json).unwrap();
        assert_eq!(trades[0].side, Side::Buy);

        // m=true means taker is seller → Sell
        let sell_json = r#"{"e":"trade","E":1640000000000,"s":"BTCUSDT","t":2,"p":"50000.00","q":"1.0","T":1640000000000,"m":true}"#;
        let trades = adapter.parse_message(sell_json).unwrap();
        assert_eq!(trades[0].side, Side::Sell);
    }

    #[test]
    fn test_side_detection_kraken() {
        let adapter = KrakenTradeAdapter::new("http://test".to_string());

        // side="buy"
        let buy_json = r#"{"channel":"trade","data":[{"symbol":"BTC/USD","price":50000.0,"qty":1.0,"side":"buy","timestamp":"2024-01-01T00:00:00Z","trade_id":1}]}"#;
        let trades = adapter.parse_message(buy_json).unwrap();
        assert_eq!(trades[0].side, Side::Buy);

        // side="sell"
        let sell_json = r#"{"channel":"trade","data":[{"symbol":"BTC/USD","price":50000.0,"qty":1.0,"side":"sell","timestamp":"2024-01-01T00:00:00Z","trade_id":2}]}"#;
        let trades = adapter.parse_message(sell_json).unwrap();
        assert_eq!(trades[0].side, Side::Sell);
    }
}

#[cfg(test)]
mod alpaca_subscriber_tests {
    use gds_common::ExchangeConfig;

    #[test]
    fn test_alpaca_config_factory() {
        let cfg = ExchangeConfig::alpaca();
        assert_eq!(cfg.name, "alpaca");
        assert!(cfg.ws_url.starts_with("wss://stream.data.alpaca.markets"));
        assert!(cfg.symbols.contains(&"AAPL".to_string()));
    }

    #[test]
    fn test_alpaca_disabled_without_credentials() {
        std::env::remove_var("ALPACA_API_KEY");
        std::env::remove_var("ALPACA_SECRET_KEY");
        let cfg = ExchangeConfig::alpaca();
        assert!(
            !cfg.enabled,
            "Alpaca must default to disabled when credentials are missing"
        );
    }
}
