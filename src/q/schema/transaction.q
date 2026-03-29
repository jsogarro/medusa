/ ============================================================================
/ transaction.q - Inter-Exchange Transaction Management
/ ============================================================================
/
/ Provides:
/   - Transaction lifecycle (pending → confirming → completed)
/   - Balance reservation and release
/   - Fee handling in same or different currency
/   - Transaction status transitions with balance updates
/
/ Dependencies:
/   - types.q (validation, constants, ID generator)
/   - exchange.q (balance operations: reserve, release, deduct, credit)
/
/ Tables:
/   - transaction: Fund transfers between exchanges (keyed by transaction_id)
/
/ Functions:
/   - Commands: createTransaction, updateTransactionStatus, updateTransactionAddresses
/   - Queries: getTransaction, getPendingTransactions, getTransactionsByExchange,
/              getTransactionsByStatus, getRecentTransactions
/   - Analytics: getTotalTransferVolume, getTotalTransferFees, getAvgConfirmationTime,
/                getTransactionFlow
/
/ State Machine:
/   pending -> confirming -> completed
/   pending -> failed
/   pending -> cancelled
/   confirming -> failed
/ ============================================================================

\d .qg

// ============================================================================
// TRANSACTION TABLE SCHEMA
// ============================================================================

transactionSchema:([]
  transaction_id: `long$();              / Unique transaction ID (auto-increment, PK)
  unique_id: `guid$();                   / GUID for distributed systems
  from_exchange: `symbol$();             / Source exchange (FK to Exchange.name)
  to_exchange: `symbol$();               / Destination exchange (FK to Exchange.name)
  currency: `symbol$();                  / Currency being transferred
  amount: `long$();                      / Transfer amount (fixed precision)
  fee: `long$();                         / Transfer fee (fixed precision)
  fee_currency: `symbol$();              / Fee currency
  status: `symbol$();                    / Transaction status
  transaction_hash: `symbol$();          / Blockchain transaction hash (if applicable)
  from_address: `symbol$();              / Source address
  to_address: `symbol$();                / Destination address
  confirmations: `long$();               / Number of confirmations (blockchain)
  time_initiated: `timestamp$();         / Transaction initiation time
  time_completed: `timestamp$();         / Transaction completion time
  time_updated: `timestamp$();           / Last update time
  meta_data: ()                          / Dictionary of transaction metadata
 );

// Primary key: transaction_id
// Indices: from_exchange, to_exchange, status, time_initiated

// Transaction status enumeration
TRANSACTION_STATUS:`pending`confirming`completed`failed`cancelled;

// ============================================================================
// TABLE INITIALIZATION
// ============================================================================

initTransactionTable:{[]
  transaction::transactionSchema;

  / Create primary key
  `transaction_id xkey `transaction;
 };

// ============================================================================
// VALIDATION FUNCTIONS
// ============================================================================

isValidTransactionStatus:{x in .qg.TRANSACTION_STATUS};

// ============================================================================
// CRUD OPERATIONS - TRANSACTION
// ============================================================================

// Initiate new transaction
// Usage: .qg.createTransaction[`coinbase; `kraken; `BTC; 2000000j; 1000j; `BTC; ...]
createTransaction:{[fromExchange; toExchange; currency; amount; fee; feeCurrency; metaData]
  / Validate inputs
  if[not .qg.isValidExchange[fromExchange];
    '"Invalid source exchange"];
  if[not .qg.isValidExchange[toExchange];
    '"Invalid destination exchange"];
  if[fromExchange = toExchange;
    '"Source and destination must be different"];
  if[not .qg.isValidCurrency[currency];
    '"Invalid currency"];
  if[not .qg.isValidCurrency[feeCurrency];
    '"Invalid fee currency"];
  if[not .qg.isPositiveAmount[amount];
    '"Amount must be positive"];

  / Check source exchange has sufficient balance for amount
  bal:.qg.getBalance[fromExchange; currency];
  if[()~bal; '"Insufficient balance: no balance record found"];
  if[bal[`available] < amount;
    '"Insufficient available balance for amount"];

  / Check fee currency balance if different
  if[currency <> feeCurrency;
    feeBal:.qg.getBalance[fromExchange; feeCurrency];
    if[()~feeBal; '"Insufficient balance: no fee currency balance record"];
    if[feeBal[`available] < fee;
      '"Insufficient available balance for fee"];
  ];
  / Generate new transaction ID and GUID
  txnId:.qg.nextId[`transaction];
  guid:.Q.w[];

  / Insert transaction
  `transaction insert (
    txnId;                               / transaction_id
    guid;                                / unique_id
    fromExchange;                        / from_exchange
    toExchange;                          / to_exchange
    currency;                            / currency
    amount;                              / amount
    fee;                                 / fee
    feeCurrency;                         / fee_currency
    `pending;                            / status
    `;                                   / transaction_hash (null initially)
    `;                                   / from_address (null initially)
    `;                                   / to_address (null initially)
    0j;                                  / confirmations
    .z.p;                                / time_initiated
    .qg.NULL_TIMESTAMP;                                 / time_completed (null)
    .z.p;                                / time_updated
    metaData                             / meta_data
  );

  / Reserve funds from source exchange
  feeAmount:$[currency=feeCurrency; fee; 0j];
  .qg.reserveBalance[fromExchange; currency; amount + feeAmount];

  txnId
 };

/ ============================================================================
/ HELPER FUNCTIONS FOR STATUS TRANSITIONS
/ ============================================================================

/ Update balances on transaction completion
updateBalancesOnComplete:{[txn]
  / Deduct from source exchange (remove from reserved)
  feeAmount:$[txn[`currency]=txn[`fee_currency]; txn[`fee]; 0j];
  .qg.deductBalance[txn[`from_exchange]; txn[`currency]; txn[`amount] + feeAmount];

  / Credit destination exchange
  .qg.creditBalance[txn[`to_exchange]; txn[`currency]; txn[`amount]];
 };

/ Update balances on transaction failure or cancellation
updateBalancesOnFailure:{[txn]
  / Release reserved funds back to available
  feeAmount:$[txn[`currency]=txn[`fee_currency]; txn[`fee]; 0j];
  .qg.releaseBalance[txn[`from_exchange]; txn[`currency]; txn[`amount] + feeAmount];
 };

/ Update transaction status with balance adjustments
/ State Transitions:
/   pending -> confirming -> completed  (normal flow)
/   pending -> failed                   (pre-confirmation failure)
/   pending -> cancelled                (user cancelled)
/   confirming -> failed                (blockchain failure)
/ Balance Effects:
/   completed: deducts from source reserved, credits destination
/   failed/cancelled: releases source reserved back to available
updateTransactionStatus:{[transactionId; newStatus; confirmations; txHash]
  / Validate status
  if[not .qg.isValidTransactionStatus[newStatus];
    '"Invalid transaction status"];

  / Get transaction
  txn:first select from transaction where transaction_id=transactionId;
  if[0 = count txn; '"Transaction not found"];

  / Update transaction record
  update status:newStatus,
    confirmations:confirmations,
    transaction_hash:txHash,
    time_completed:$[newStatus in `completed`failed`cancelled; .z.p; time_completed],
    time_updated:.z.p
    from `transaction where transaction_id=transactionId;

  / Update balances based on new status
  $[newStatus = `completed; updateBalancesOnComplete[txn];
    newStatus in `failed`cancelled; updateBalancesOnFailure[txn];
    ()
  ];

  transactionId
 };

// Update transaction addresses
updateTransactionAddresses:{[transactionId; fromAddr; toAddr]
  update from_address:fromAddr, to_address:toAddr, time_updated:.z.p
    from `transaction where transaction_id=transactionId;

  transactionId
 };

// Get transaction by ID
getTransaction:{[transactionId]
  first select from transaction where transaction_id=transactionId
 };

// Get pending transactions
getPendingTransactions:{[]
  select from transaction where status in `pending`confirming
 };

// Get transactions by exchange
getTransactionsByExchange:{[exchangeName]
  select from transaction
    where from_exchange=exchangeName or to_exchange=exchangeName
 };

// Get transactions by status
getTransactionsByStatus:{[status]
  select from transaction where status=status
 };

// Get recent transactions
getRecentTransactions:{[n]
  idx:n sublist idesc exec time_initiated from transaction;
  transaction idx
 };

// ============================================================================
// QUERY FUNCTIONS
// ============================================================================

// Get total transferred volume
getTotalTransferVolume:{[fromExchange; toExchange; currency; startTime; endTime]
  exec sum amount from transaction
    where from_exchange=fromExchange,
          to_exchange=toExchange,
          currency=currency,
          time_initiated within (startTime; endTime),
          status=`completed
 };

// Get total transfer fees
getTotalTransferFees:{[currency; startTime; endTime]
  exec sum fee from transaction
    where fee_currency=currency,
          time_initiated within (startTime; endTime),
          status=`completed
 };

// Get average confirmation time
getAvgConfirmationTime:{[currency]
  exec avg time_completed - time_initiated
    from transaction
    where currency=currency, status=`completed
 };

// Get transaction flow between exchanges
getTransactionFlow:{[startTime; endTime]
  select
    transferCount:count i,
    totalAmount:sum amount,
    avgAmount:avg amount,
    totalFees:sum fee
    by from_exchange, to_exchange, currency, status
    from transaction
    where time_initiated within (startTime; endTime)
 };

\d .

/ Export namespace
-1 "  Transaction table loaded: transaction with balance management";
