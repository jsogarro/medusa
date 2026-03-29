/ ============================================================================
/ base.q - Exchange Wrapper Base Interface
/ ============================================================================
/
/ Provides:
/   - Abstract exchange interface with lifecycle state machine
/   - Order type enumeration and validation
/   - Order lifecycle state machine with transition validation
/   - Dispatch to exchange-specific implementations via registry
/
/ Dependencies:
/   - types.q (validation, constants)
/   - registry.q (exchange implementation registry)
/
/ Functions:
/   - placeOrder: Place an order on an exchange
/   - cancelOrder: Cancel an existing order
/   - getBalance: Get balance for a currency
/   - getOrderbook: Get current orderbook snapshot
/   - getOpenOrders: Get all open orders
/   - getPosition: Get current position for a trading pair
/ ============================================================================

\d .exchange

// ============================================================================
// ENUMERATIONS
// ============================================================================

/ Order types
ORDER_TYPE:`market`limit`stop_loss`take_profit;

/ Order lifecycle states
ORDER_STATE:`pending`open`partially_filled`filled`cancelled`rejected`expired;

/ Order sides
ORDER_SIDE:`buy`sell;

// ============================================================================
// STATE MACHINE - ORDER LIFECYCLE
// ============================================================================

/ Valid state transitions
/ State machine: pending → open → partially_filled → filled
/                 pending → rejected
/                 open → cancelled
/                 partially_filled → filled
/                 partially_filled → cancelled
validTransitions:()!();
validTransitions[`pending]:`open`rejected;
validTransitions[`open]:`partially_filled`filled`cancelled`expired;
validTransitions[`partially_filled]:`filled`cancelled`expired;
validTransitions[`filled]:();
validTransitions[`cancelled]:();
validTransitions[`rejected]:();
validTransitions[`expired]:();

/ Check if state transition is valid
/ @param fromState symbol - Current state
/ @param toState symbol - Target state
/ @return boolean - True if transition is valid
isValidTransition:{[fromState;toState]
  if[not fromState in ORDER_STATE; :0b];
  if[not toState in ORDER_STATE; :0b];
  toState in validTransitions[fromState]
 };

// ============================================================================
// VALIDATION FUNCTIONS
// ============================================================================

/ Validate order type
isValidOrderType:{x in ORDER_TYPE};

/ Validate order state
isValidOrderState:{x in ORDER_STATE};

/ Validate order side
isValidOrderSide:{x in ORDER_SIDE};

/ Validate order parameters
/ @param orderType symbol - Order type
/ @param side symbol - Buy or sell
/ @param price long - Price (can be null for market orders)
/ @param quantity long - Order quantity
validateOrderParams:{[orderType;side;price;quantity]
  / Validate order type
  if[not isValidOrderType[orderType];
    '"Invalid order type: ",string orderType];

  / Validate side
  if[not isValidOrderSide[side];
    '"Invalid order side: ",string side];

  / Validate quantity
  if[not .qg.isPositiveAmount[quantity];
    '"Quantity must be positive"];

  / Validate price for limit orders
  if[(orderType in `limit`stop_loss`take_profit) and not .qg.isValidPrice[price];
    '"Limit/stop orders require valid price"];

  1b
 };

// ============================================================================
// EXCHANGE INTERFACE (dispatch to implementations)
// ============================================================================

/ Place order on exchange
/ @param exchangeName symbol - Exchange name
/ @param pair symbol - Trading pair (e.g., `BTCUSD)
/ @param orderType symbol - Order type (market, limit, etc.)
/ @param side symbol - Buy or sell
/ @param price long - Order price (null for market orders)
/ @param quantity long - Order quantity
/ @return dict - Order response with orderId and status
placeOrder:{[exchangeName;pair;orderType;side;price;quantity]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  validateOrderParams[orderType;side;price;quantity];

  / Dispatch to exchange implementation
  impl:.exchange.registry.getImplementation[exchangeName];
  impl[`placeOrder][pair;orderType;side;price;quantity]
 };

/ Cancel order on exchange
/ @param exchangeName symbol - Exchange name
/ @param orderId long - Order ID to cancel
/ @return dict - Cancellation response
cancelOrder:{[exchangeName;orderId]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  if[orderId <= 0;
    '"Invalid order ID"];

  / Dispatch to exchange implementation
  impl:.exchange.registry.getImplementation[exchangeName];
  impl[`cancelOrder][orderId]
 };

/ Get balance for currency
/ @param exchangeName symbol - Exchange name
/ @param currency symbol - Currency code
/ @return dict - Balance dict with amount, available, reserved
getBalance:{[exchangeName;currency]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  if[not .qg.isValidCurrency[currency];
    '"Invalid currency"];

  / Dispatch to exchange implementation
  impl:.exchange.registry.getImplementation[exchangeName];
  impl[`getBalance][currency]
 };

/ Get orderbook snapshot
/ @param exchangeName symbol - Exchange name
/ @param pair symbol - Trading pair
/ @return table - Orderbook with bids and asks
getOrderbook:{[exchangeName;pair]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];

  / Dispatch to exchange implementation
  impl:.exchange.registry.getImplementation[exchangeName];
  impl[`getOrderbook][pair]
 };

/ Get open orders for pair
/ @param exchangeName symbol - Exchange name
/ @param pair symbol - Trading pair
/ @return table - Open orders
getOpenOrders:{[exchangeName;pair]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];

  / Dispatch to exchange implementation
  impl:.exchange.registry.getImplementation[exchangeName];
  impl[`getOpenOrders][pair]
 };

/ Get position for trading pair
/ @param exchangeName symbol - Exchange name
/ @param pair symbol - Trading pair
/ @return dict - Position dict with size, side, entry price
getPosition:{[exchangeName;pair]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];

  / Dispatch to exchange implementation
  impl:.exchange.registry.getImplementation[exchangeName];
  impl[`getPosition][pair]
 };

\d .

/ Export namespace
-1 "  Exchange base interface loaded: .exchange namespace with order lifecycle state machine";
