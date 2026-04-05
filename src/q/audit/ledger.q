/ ============================================================================
/ ledger.q - Ledger Consistency Audit
/ ============================================================================
/
/ Performs full consistency check across all ledger transactions:
/   - Double-entry bookkeeping (debits = credits per currency)
/   - No orphaned transactions (broken parent references)
/   - Timestamp monotonicity (no backdated transactions)
/   - Currency validity (all currencies recognized by money system)
/
/ Dependencies:
/   - audit.q (core infrastructure)
/   - lib/money.q (.money.validCurrency)
/   - schema/transaction.q (.qg.transaction table)
/
/ Usage:
/   .audit.LEDGER.validate[]
/   .audit.run[`LEDGER_AUDIT]
/ ============================================================================

\d .audit

/ ============================================================================
/ LEDGER AUDIT NAMESPACE
/ ============================================================================

/ Tolerance for balance comparisons
LEDGER.tolerance:0.00000001f;

/ ============================================================================
/ CONSISTENCY CHECKS
/ ============================================================================

/ Verify all transactions reference valid currencies
/ @param txns table - Transaction table
/ @return dict - (valid; invalidCurrencies; invalidTxIds)
LEDGER.checkCurrencies:{[txns]
  if[0=count txns; :(`valid`invalidCurrencies`invalidTxIds)!(1b;`symbol$();`long$())];

  / Gather all currencies mentioned
  allCurrencies:distinct exec currency from txns;
  / Add fee_currency if present
  if[`fee_currency in cols txns;
    allCurrencies:distinct allCurrencies,exec fee_currency from txns where not null fee_currency;
  ];

  / Check against money system
  validFn:@[{.money.validCurrency[x]};;{0b}];
  invalidCurrencies:allCurrencies where not validFn each allCurrencies;

  / Find affected transaction IDs
  invalidTxIds:$[0<count invalidCurrencies;
    exec transaction_id from txns where currency in invalidCurrencies;
    `long$()
  ];

  (`valid`invalidCurrencies`invalidTxIds)!(0=count invalidCurrencies; invalidCurrencies; invalidTxIds)
 };

/ Verify double-entry bookkeeping: net flow per currency should balance
/ For a closed system, sum of all amounts grouped by type should net to zero.
/ In practice we verify credits equal debits per currency.
/ @param txns table - Transaction table
/ @return dict - (balanced; imbalances)
LEDGER.checkDoubleEntry:{[txns]
  if[0=count txns; :(`balanced`imbalances)!(1b;([] currency:`symbol$(); totalDebit:`float$(); totalCredit:`float$(); delta:`float$()))];

  / Classify transaction types as debit or credit
  debitTypes:`withdrawal`debit`sell_fill`fee;
  creditTypes:`deposit`credit`buy_fill;

  debits:select totalDebit:sum amount by currency from txns where transaction_type in debitTypes;
  credits:select totalCredit:sum amount by currency from txns where transaction_type in creditTypes;

  / Full outer join via union of currencies
  allCurrs:distinct (exec currency from debits),(exec currency from credits);
  summary:([] currency:allCurrs);
  summary:summary lj `currency xkey 0!debits;
  summary:summary lj `currency xkey 0!credits;
  summary:update totalDebit:0f^totalDebit, totalCredit:0f^totalCredit from summary;
  summary:update delta:abs totalDebit - totalCredit from summary;

  imbalances:select from summary where delta>.audit.LEDGER.tolerance;

  (`balanced`imbalances)!(0=count imbalances; imbalances)
 };

/ Verify no orphaned transactions (parent references exist)
/ @param txns table - Transaction table
/ @return dict - (valid; orphanedTxIds)
LEDGER.checkOrphanedTransactions:{[txns]
  / If no parent reference column, skip check
  if[not `parent_transaction_id in cols txns;
    :(`valid`orphanedTxIds)!(1b;`long$())
  ];
  if[0=count txns; :(`valid`orphanedTxIds)!(1b;`long$())];

  allTxIds:exec transaction_id from txns;
  referencedIds:exec distinct parent_transaction_id from txns where not null parent_transaction_id;
  orphanedIds:referencedIds except allTxIds;

  (`valid`orphanedTxIds)!(0=count orphanedIds; orphanedIds)
 };

/ Verify timestamps are monotonically increasing (sorted by transaction_id)
/ @param txns table - Transaction table
/ @return dict - (valid; backdatedTxIds)
LEDGER.checkTimestamps:{[txns]
  if[2>count txns; :(`valid`backdatedTxIds)!(1b;`long$())];

  sorted:`transaction_id xasc txns;
  timestamps:exec time_created from sorted;
  / If column is named differently, try common alternatives
  if[all null timestamps;
    if[`timestamp in cols sorted; timestamps:exec timestamp from sorted];
  ];
  if[all null timestamps; :(`valid`backdatedTxIds)!(1b;`long$())];

  / Check each consecutive pair
  diffs:1_ timestamps - -1_ timestamps;
  backdatedIndices:where 0>diffs;
  backdatedTxIds:$[0<count backdatedIndices;
    exec transaction_id from sorted where i in backdatedIndices+1;
    `long$()
  ];

  (`valid`backdatedTxIds)!(0=count backdatedTxIds; backdatedTxIds)
 };

/ ============================================================================
/ MAIN VALIDATION FUNCTION
/ ============================================================================

/ Main ledger audit
/ @return dict - Standardized audit result
LEDGER.validate:{[]
  / Fetch all transactions
  if[not `transaction in key `.qg;
    :.audit.newResult[`LEDGER_AUDIT;`WARNING;();enlist "Transaction table not found";()!()]
  ];
  txns:.qg.transaction;
  if[0=count txns;
    :.audit.newResult[`LEDGER_AUDIT;`PASS;();enlist "No transactions to audit";`totalTransactions`allChecksValid!(0;1b)]
  ];

  / Run all consistency checks
  currencyCheck:LEDGER.checkCurrencies[txns];
  doubleEntryCheck:LEDGER.checkDoubleEntry[txns];
  orphanedCheck:LEDGER.checkOrphanedTransactions[txns];
  timestampCheck:LEDGER.checkTimestamps[txns];

  / Build errors
  errors:();

  if[not currencyCheck`valid;
    errors,:enlist "Invalid currencies found: ",(.Q.s1 currencyCheck`invalidCurrencies)," in ",(string count currencyCheck`invalidTxIds)," transactions"];
  if[not doubleEntryCheck`balanced;
    errors,:enlist "Double-entry imbalance: ",(string count doubleEntryCheck`imbalances)," currencies not balanced"];
  if[not orphanedCheck`valid;
    errors,:enlist "Orphaned transactions: ",(string count orphanedCheck`orphanedTxIds)," transactions reference non-existent parent IDs"];
  if[not timestampCheck`valid;
    errors,:enlist "Backdated transactions: ",(string count timestampCheck`backdatedTxIds)," transactions have earlier timestamps than predecessors"];

  status:$[0<count errors;`FAIL;`PASS];

  metrics:`totalTransactions`currencyCheckValid`doubleEntryBalanced`orphanedCheckValid`timestampCheckValid!(
    count txns; currencyCheck`valid; doubleEntryCheck`balanced; orphanedCheck`valid; timestampCheck`valid);

  .audit.newResult[`LEDGER_AUDIT;status;errors;();metrics]
 };

/ ============================================================================
/ CRITICAL FAILURE HANDLER
/ ============================================================================

/ Handle critical ledger failures — halt trading and alert
/ @param errors list - Error messages from the audit
LEDGER.handleCriticalFailure:{[errors]
  -2 "!!! CRITICAL LEDGER AUDIT FAILURE !!!";
  {-2 "  ",x} each errors;
  / Halt all strategies if engine is available
  @[{.engine.loop.haltAll["Critical ledger audit failure"]};::;{-2 "Warning: could not halt strategies: ",x}];
 };

/ ============================================================================
/ REGISTRATION
/ ============================================================================

.audit.registerType[`LEDGER_AUDIT; "Ledger Audit"; "Full consistency check: double-entry, orphans, timestamps, currencies"; `.audit.LEDGER.validate];

\d .
