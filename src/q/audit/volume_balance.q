/ ============================================================================
/ volume_balance.q - Volume (Crypto) Balance Audit
/ ============================================================================
/
/ Verifies that crypto asset balances on the exchange match the calculated
/ balance from the ledger/transaction history. Discrepancies indicate
/ missing transactions or incorrect ledger entries.
/
/ Dependencies:
/   - audit.q (core infrastructure)
/   - lib/money.q (.money.new, .money.validCurrency)
/   - exchange/coordinator.q (.exchange.coordinator.getBalances)
/   - schema/exchange.q (.qg.balance table)
/
/ Usage:
/   .audit.VOLUME_BALANCE.validate[]
/   .audit.run[`VOLUME_BALANCE_AUDIT]
/ ============================================================================

\d .audit

/ ============================================================================
/ VOLUME BALANCE AUDIT NAMESPACE
/ ============================================================================

/ Tolerance: 1 satoshi for BTC-precision assets
VOLUME_BALANCE.tolerance:0.00000001f;

/ Default crypto currencies to audit
VOLUME_BALANCE.defaultCurrencies:`BTC`ETH;

/ Compare two Money-like amounts for a given currency
/ @param amount1 float - First amount
/ @param amount2 float - Second amount
/ @return dict - (matches; delta)
VOLUME_BALANCE.compareAmounts:{[amount1;amount2]
  delta:abs amount1 - amount2;
  `matches`delta!(delta<=.audit.VOLUME_BALANCE.tolerance; delta)
 };

/ Get crypto balance from exchange via coordinator
/ @param currency symbol - Currency to check
/ @return float - Balance amount (0f if unavailable)
VOLUME_BALANCE.getExchangeBalance:{[currency]
  / Try coordinator first, fall back to balance table
  bal:@[{[c]
    balances:.exchange.coordinator.getBalances[];
    res:exec first balance from balances where currency=c;
    $[null res;0f;res]
  }[currency];::;{0f}];
  bal
 };

/ Calculate crypto balance from transaction history (ledger)
/ Sums all credits minus debits for the currency
/ @param currency symbol - Currency to calculate
/ @return float - Calculated balance
VOLUME_BALANCE.calculateLedgerBalance:{[currency]
  / Use transaction table if it exists
  if[not `transaction in key `.qg; :0f];
  txns:.qg.transaction;
  if[0=count txns; :0f];

  / Sum credits (deposits, buy fills) and debits (withdrawals, sell fills)
  credits:exec sum amount from txns where currency=currency, transaction_type in `deposit`credit`buy_fill;
  debits:exec sum amount from txns where currency=currency, transaction_type in `withdrawal`debit`sell_fill;
  credits - debits
 };

/ ============================================================================
/ MAIN VALIDATION FUNCTION
/ ============================================================================

/ Main volume balance audit
/ @return dict - Standardized audit result
VOLUME_BALANCE.validate:{[]
  / Get currencies to audit from config or use defaults
  currencies:$[
    @[{.conf.get[`audit;`volume_currencies;.audit.VOLUME_BALANCE.defaultCurrencies]};::;{.audit.VOLUME_BALANCE.defaultCurrencies}];
    .audit.VOLUME_BALANCE.defaultCurrencies
  ];
  / Ensure we have a symbol list
  if[not 11h=type currencies; currencies:.audit.VOLUME_BALANCE.defaultCurrencies];

  / Check balance for each currency
  errors:();
  checkResults:();

  {[currency]
    exchangeBal:.audit.VOLUME_BALANCE.getExchangeBalance[currency];
    ledgerBal:.audit.VOLUME_BALANCE.calculateLedgerBalance[currency];
    comp:.audit.VOLUME_BALANCE.compareAmounts[exchangeBal;ledgerBal];

    checkResults,::(`currency`exchangeAmount`ledgerAmount`delta`matches)!(currency;exchangeBal;ledgerBal;comp`delta;comp`matches);

    if[not comp`matches;
      errors,::enlist "Balance mismatch for ",(string currency),": exchange=",(string exchangeBal)," ledger=",(string ledgerBal)," delta=",string comp`delta;
    ];
  } each currencies;

  resultTable:$[0<count checkResults; flip `currency`exchangeAmount`ledgerAmount`delta`matches!flip checkResults; ([] currency:`symbol$(); exchangeAmount:`float$(); ledgerAmount:`float$(); delta:`float$(); matches:`boolean$())];

  status:$[0<count errors;`FAIL;`PASS];
  metrics:`currenciesChecked`mismatchCount`results!(count currencies; sum not resultTable`matches; resultTable);

  .audit.newResult[`VOLUME_BALANCE_AUDIT;status;errors;();metrics]
 };

/ ============================================================================
/ REGISTRATION
/ ============================================================================

.audit.registerType[`VOLUME_BALANCE_AUDIT; "Volume Balance Audit"; "Verifies crypto balances on exchange match ledger calculation"; `.audit.VOLUME_BALANCE.validate];

\d .
