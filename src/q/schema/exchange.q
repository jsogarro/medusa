/ ============================================================================
/ exchange.q - Exchange Account Management
/ ============================================================================
/
/ Provides:
/   - Exchange account CRUD (exchange table)
/   - Balance tracking per currency (balance table)
/   - Leveraged positions (position table)
/   - Target balance management (target table)
/   - Balance operation helpers (reserve, release, deduct, credit)
/
/ Dependencies:
/   - types.q (validation, constants, ID generator)
/
/ Tables:
/   - exchange: Exchange accounts with metadata
/   - balance: Currency balances (keyed by exchange_name, currency)
/   - position: Leveraged trading positions
/   - target: Desired balance targets with priorities
/
/ Functions:
/   - Exchange: createExchange, updateExchange, deactivateExchange, getExchange
/   - Balance: updateBalance, getBalance, getExchangeBalances
/   - Balance Ops: reserveBalance, releaseBalance, deductBalance, creditBalance
/   - Position: openPosition, updatePosition, closePosition, getOpenPositions
/   - Target: createTarget, updateTarget, deactivateTarget, getActiveTargets
/ ============================================================================

\d .qg

// ============================================================================
// EXCHANGE TABLE SCHEMA
// ============================================================================

// Create Exchange table
// Stores exchange account information and current state
exchangeSchema:([]
  name: `symbol$();                      / Exchange name (primary key, unique)
  time_created: `timestamp$();           / Account creation timestamp
  time_updated: `timestamp$();           / Last update timestamp
  is_active: `boolean$();                / Whether exchange is active
  api_key_hash: `symbol$();              / Hashed API key (for reference)
  meta_data: ()                          / Dictionary of exchange-specific metadata
 );

// ============================================================================
// BALANCE TABLE SCHEMA
// ============================================================================

// Balances are stored separately with one row per currency per exchange
// This enables efficient querying and updates
balanceSchema:([]
  exchange_name: `symbol$();             / Foreign key to Exchange.name
  currency: `symbol$();                  / Currency symbol (USD, BTC, etc.)
  amount: `long$();                      / Balance amount (fixed precision)
  available: `long$();                   / Available balance (not in orders)
  reserved: `long$();                    / Reserved balance (in open orders)
  time_updated: `timestamp$()            / Last update timestamp
 );

// Create unique index on (exchange_name, currency)
// Key: `exchange_name`currency

// ============================================================================
// POSITION TABLE SCHEMA
// ============================================================================

// Positions track leveraged/margin trading positions
positionSchema:([]
  position_id: `long$();                 / Unique position ID (auto-increment)
  exchange_name: `symbol$();             / Foreign key to Exchange.name
  symbol: `symbol$();                    / Trading pair (e.g., `BTCUSD)
  side: `symbol$();                      / `long or `short
  size: `long$();                        / Position size (fixed precision)
  entry_price: `long$();                 / Average entry price (fixed precision)
  current_price: `long$();               / Current market price (fixed precision)
  liquidation_price: `long$();           / Liquidation price (fixed precision)
  unrealized_pnl: `long$();              / Unrealized P&L (fixed precision)
  leverage: `float$();                   / Leverage multiplier
  time_opened: `timestamp$();            / Position open time
  time_updated: `timestamp$();           / Last update time
  is_open: `boolean$()                   / Whether position is still open
 );

// Primary key: position_id
// Index: exchange_name, symbol, is_open

// ============================================================================
// TARGET TABLE SCHEMA
// ============================================================================

// Targets define desired balances/positions for each exchange
targetSchema:([]
  target_id: `long$();                   / Unique target ID (auto-increment)
  exchange_name: `symbol$();             / Foreign key to Exchange.name
  currency: `symbol$();                  / Currency for balance target
  target_amount: `long$();               / Desired balance (fixed precision)
  tolerance: `long$();                   / Acceptable deviation (fixed precision)
  priority: `long$();                    / Priority level (1=highest)
  is_active: `boolean$();                / Whether target is active
  time_created: `timestamp$();           / Target creation time
  time_updated: `timestamp$()            / Last update time
 );

// Primary key: target_id
// Index: exchange_name, currency, is_active

// ============================================================================
// TABLE INITIALIZATION
// ============================================================================

// Initialize all exchange-related tables
initExchangeTables:{[]
  exchange::exchangeSchema;
  balance::balanceSchema;
  position::positionSchema;
  target::targetSchema;

  / Create keyed tables for O(1) lookups
  balance::`exchange_name`currency xkey balance;
  position::`position_id xkey position;
  target::`target_id xkey target;
 };

// ============================================================================
// CRUD OPERATIONS - EXCHANGE
// ============================================================================

// Create new exchange account
// Usage: .qg.createExchange[`coinbase; `abc123hash; ()!()]
createExchange:{[exchangeName; apiKeyHash; metaData]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  if[exchangeName in exec name from exchange;
    '"Exchange already exists"];

  / Insert row
  `exchange insert (
    exchangeName;                        / name
    .z.p;                                / time_created
    .z.p;                                / time_updated
    1b;                                  / is_active
    apiKeyHash;                          / api_key_hash
    metaData                             / meta_data
  );

  exchangeName
 };

// Update exchange metadata
updateExchange:{[exchangeName; metaData]
  if[not exchangeName in exec name from exchange;
    '"Exchange not found"];

  update meta_data:metaData, time_updated:.z.p
    from `exchange where name=exchangeName;

  exchangeName
 };

// Deactivate exchange
deactivateExchange:{[exchangeName]
  update is_active:0b, time_updated:.z.p
    from `exchange where name=exchangeName;

  exchangeName
 };

// Get exchange info
getExchange:{[exchangeName]
  first select from exchange where name=exchangeName
 };

// ============================================================================
// CRUD OPERATIONS - BALANCE
// ============================================================================

// Update balance for exchange/currency pair
// Usage: .qg.updateBalance[`coinbase; `BTC; 1500000j; 1200000j; 300000j]
updateBalance:{[exchangeName; currency; amount; available; reserved]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  if[not .qg.isValidCurrency[currency];
    '"Invalid currency"];
  if[amount <> available + reserved;
    '"Amount must equal available + reserved"];

  / Upsert using keyed table
  `balance upsert (
    exchangeName; currency; amount; available; reserved; .z.p
  );

  (exchangeName; currency)
 };

// Get balance for exchange/currency
// Optimized: Uses keyed table O(1) lookup
getBalance:{[exchangeName; currency]
  balance[(exchangeName; currency)]
 };

// Get all balances for exchange
getExchangeBalances:{[exchangeName]
  select from balance where exchange_name=exchangeName
 };

// ============================================================================
// BALANCE OPERATION HELPERS (for transaction module)
// ============================================================================

// Reserve balance (move from available to reserved)
reserveBalance:{[exchangeName; currency; amount]
  bal:getBalance[exchangeName; currency];
  if[()~bal; '"Cannot reserve: no balance record found"];
  if[bal[`available] < amount; '"Cannot reserve: insufficient available balance"];

  updateBalance[
    exchangeName; currency;
    bal[`amount];
    bal[`available] - amount;
    bal[`reserved] + amount
  ]
 };

// Release balance (move from reserved back to available)
releaseBalance:{[exchangeName; currency; amount]
  bal:getBalance[exchangeName; currency];
  if[()~bal; '"Cannot release: no balance record found"];
  if[bal[`reserved] < amount; '"Cannot release: insufficient reserved balance"];

  updateBalance[
    exchangeName; currency;
    bal[`amount];
    bal[`available] + amount;
    bal[`reserved] - amount
  ]
 };

// Deduct balance (remove from total and reserved)
deductBalance:{[exchangeName; currency; amount]
  bal:getBalance[exchangeName; currency];
  if[()~bal; '"Cannot deduct: no balance record found"];
  if[bal[`reserved] < amount; '"Cannot deduct: insufficient reserved balance"];

  updateBalance[
    exchangeName; currency;
    bal[`amount] - amount;
    bal[`available];
    bal[`reserved] - amount
  ]
 };

// Credit balance (add to total and available)
creditBalance:{[exchangeName; currency; amount]
  bal:getBalance[exchangeName; currency];

  / If no balance exists, create it
  $[()~bal;
    updateBalance[exchangeName; currency; amount; amount; 0j];
    / Otherwise update existing
    updateBalance[
      exchangeName; currency;
      bal[`amount] + amount;
      bal[`available] + amount;
      bal[`reserved]
    ]
  ]
 };

// ============================================================================
// CRUD OPERATIONS - POSITION
// ============================================================================

// Open new position
openPosition:{[exchangeName; symbol; side; size; entryPrice; leverage]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  if[not side in `long`short;
    '"Side must be `long or `short"];
  if[not .qg.isPositiveAmount[size];
    '"Size must be positive"];
  if[not .qg.isValidPrice[entryPrice];
    '"Invalid entry price"];

  / Generate new position ID
  posId:.qg.nextId[`position];

  / Insert position
  `position insert (
    posId;                               / position_id
    exchangeName;                        / exchange_name
    symbol;                              / symbol
    side;                                / side
    size;                                / size
    entryPrice;                          / entry_price
    entryPrice;                          / current_price (initially entry)
    .qg.NULL_LONG;                                 / liquidation_price (TBD)
    0j;                                  / unrealized_pnl
    leverage;                            / leverage
    .z.p;                                / time_opened
    .z.p;                                / time_updated
    1b                                   / is_open
  );

  posId
 };

// Update position current price and P&L
updatePosition:{[positionId; currentPrice]
  / Get position
  pos:first select from position where position_id=positionId;

  if[0 = count pos; '"Position not found"];

  / Calculate unrealized P&L
  multiplier:$[pos[`side]=`long; 1; -1];
  priceDiff:currentPrice - pos[`entry_price];
  unrealizedPnl:multiplier * priceDiff * pos[`size];

  / Update position
  update current_price:currentPrice, unrealized_pnl:unrealizedPnl,
    time_updated:.z.p
    from `position where position_id=positionId;

  positionId
 };

// Close position
closePosition:{[positionId]
  update is_open:0b, time_updated:.z.p
    from `position where position_id=positionId;

  positionId
 };

// Get open positions for exchange
getOpenPositions:{[exchangeName]
  select from position
    where exchange_name=exchangeName, is_open=1b
 };

// ============================================================================
// CRUD OPERATIONS - TARGET
// ============================================================================

// Create balance target
createTarget:{[exchangeName; currency; targetAmount; tolerance; priority]
  / Validate inputs
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name"];
  if[not .qg.isValidCurrency[currency];
    '"Invalid currency"];

  / Generate new target ID
  tgtId:.qg.nextId[`target];

  / Insert target
  `target insert (
    tgtId;                               / target_id
    exchangeName;                        / exchange_name
    currency;                            / currency
    targetAmount;                        / target_amount
    tolerance;                           / tolerance
    priority;                            / priority
    1b;                                  / is_active
    .z.p;                                / time_created
    .z.p                                 / time_updated
  );

  tgtId
 };

// Update target
updateTarget:{[targetId; targetAmount; tolerance; priority]
  update target_amount:targetAmount, tolerance:tolerance,
    priority:priority, time_updated:.z.p
    from `target where target_id=targetId;

  targetId
 };

// Deactivate target
deactivateTarget:{[targetId]
  update is_active:0b, time_updated:.z.p
    from `target where target_id=targetId;

  targetId
 };

// Get active targets for exchange
getActiveTargets:{[exchangeName]
  select from target
    where exchange_name=exchangeName, is_active=1b
 };

\d .

/ Export namespace
-1 "  Exchange tables loaded: exchange, balance, position, target";
