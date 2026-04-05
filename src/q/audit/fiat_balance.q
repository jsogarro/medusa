/ ============================================================================
/ fiat_balance.q - Fiat Balance Audit
/ ============================================================================
/
/ Verifies that fiat currency balances (USD, EUR, etc.) on the exchange
/ match the calculated balance from the ledger. Uses currency-specific
/ precision for rounding (2 decimals for USD/EUR, 0 for JPY).
/
/ Dependencies:
/   - audit.q (core infrastructure)
/   - lib/money.q (.money.precision, .money.round)
/   - exchange/coordinator.q (.exchange.coordinator.getBalances)
/   - schema/transaction.q (transaction history)
/
/ Usage:
/   .audit.FIAT_BALANCE.validate[]
/   .audit.run[`FIAT_BALANCE_AUDIT]
/ ============================================================================

\d .audit

/ ============================================================================
/ FIAT BALANCE AUDIT NAMESPACE
/ ============================================================================

/ Tolerance: 1 cent for fiat (currency-specific rounding applied before comparison)
FIAT_BALANCE.tolerance:0.01f;

/ Default fiat currencies to audit
FIAT_BALANCE.defaultCurrencies:`USD`EUR;

/ Compare two fiat amounts with currency-aware rounding
/ @param amount1 float - First amount
/ @param amount2 float - Second amount
/ @param currency symbol - Currency for precision lookup
/ @return dict - (matches; delta)
FIAT_BALANCE.compareAmounts:{[amount1;amount2;currency]
  / Round both to currency precision before comparing
  a1:@[.money.round;(amount1;currency);{[a;c;e] a}[amount1;currency]];
  a2:@[.money.round;(amount2;currency);{[a;c;e] a}[amount2;currency]];
  delta:abs a1 - a2;
  `matches`delta!(delta<=.audit.FIAT_BALANCE.tolerance; delta)
 };

/ Get fiat balance from exchange
/ @param currency symbol - Currency to check
/ @return float - Balance amount
FIAT_BALANCE.getExchangeBalance:{[currency]
  @[{[c]
    balances:.exchange.coordinator.getBalances[];
    res:exec first balance from balances where currency=c;
    $[null res;0f;res]
  }[currency];::;{0f}]
 };

/ Calculate fiat balance from transaction history
/ @param currency symbol - Currency to calculate
/ @return float - Calculated balance
FIAT_BALANCE.calculateLedgerBalance:{[currency]
  if[not `transaction in key `.qg; :0f];
  txns:.qg.transaction;
  if[0=count txns; :0f];

  credits:exec sum amount from txns where currency=currency, transaction_type in `deposit`credit`sell_fill;
  debits:exec sum amount from txns where currency=currency, transaction_type in `withdrawal`debit`buy_fill;
  credits - debits
 };

/ ============================================================================
/ MAIN VALIDATION FUNCTION
/ ============================================================================

/ Main fiat balance audit
/ @return dict - Standardized audit result
FIAT_BALANCE.validate:{[]
  currencies:$[
    @[{.conf.get[`audit;`fiat_currencies;.audit.FIAT_BALANCE.defaultCurrencies]};::;{.audit.FIAT_BALANCE.defaultCurrencies}];
    .audit.FIAT_BALANCE.defaultCurrencies
  ];
  if[not 11h=type currencies; currencies:.audit.FIAT_BALANCE.defaultCurrencies];

  errors:();
  checkResults:();

  {[currency]
    exchangeBal:.audit.FIAT_BALANCE.getExchangeBalance[currency];
    ledgerBal:.audit.FIAT_BALANCE.calculateLedgerBalance[currency];
    comp:.audit.FIAT_BALANCE.compareAmounts[exchangeBal;ledgerBal;currency];

    checkResults,::(`currency`exchangeAmount`ledgerAmount`delta`matches)!(currency;exchangeBal;ledgerBal;comp`delta;comp`matches);

    if[not comp`matches;
      errors,::enlist "Fiat balance mismatch for ",(string currency),": exchange=",(string exchangeBal)," ledger=",(string ledgerBal)," delta=",string comp`delta;
    ];
  } each currencies;

  resultTable:$[0<count checkResults; flip `currency`exchangeAmount`ledgerAmount`delta`matches!flip checkResults; ([] currency:`symbol$(); exchangeAmount:`float$(); ledgerAmount:`float$(); delta:`float$(); matches:`boolean$())];

  status:$[0<count errors;`FAIL;`PASS];
  metrics:`currenciesChecked`mismatchCount`results!(count currencies; sum not resultTable`matches; resultTable);

  .audit.newResult[`FIAT_BALANCE_AUDIT;status;errors;();metrics]
 };

/ ============================================================================
/ REGISTRATION
/ ============================================================================

.audit.registerType[`FIAT_BALANCE_AUDIT; "Fiat Balance Audit"; "Verifies fiat balances on exchange match ledger calculation"; `.audit.FIAT_BALANCE.validate];

\d .
