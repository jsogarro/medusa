/ ============================================================================
/ test_options_schema.q - Options Schema Tests
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Tests:
/   - Schema creation and structure
/   - Insert and query operations
/   - Contract ID validation
/   - Fixed-precision price handling
/ ============================================================================

/ Load dependencies
\l src/q/schema/options.q
\l src/q/lib/money.q

\l tests/q/test_framework.q

/ Local [cond;msg] assertion delegates to .test.assert[msg;cond] so the
/ framework's pass/fail counters tick correctly. Defined at root namespace
/ so .test.run discovers the test_* functions below.
assert:{[condition;msg]
  .test.assert[msg; condition]
 };

// ============================================================================
// SCHEMA STRUCTURE TESTS
// ============================================================================

test_optionSchemaStructure:{[]
  -1 "Testing schema structure...";

  / Test optionContract table exists and has correct columns
  assert[`optionContract in tables `.schema; "optionContract table exists"];
  assert[`contractId in cols .schema.optionContract; "optionContract has contractId"];
  assert[`underlying in cols .schema.optionContract; "optionContract has underlying"];
  assert[`expiry in cols .schema.optionContract; "optionContract has expiry"];
  assert[`strike in cols .schema.optionContract; "optionContract has strike"];
  assert[`optionType in cols .schema.optionContract; "optionContract has optionType"];

  / Test optionQuote table exists
  assert[`optionQuote in tables `.schema; "optionQuote table exists"];
  assert[`timestamp in cols .schema.optionQuote; "optionQuote has timestamp"];
  assert[`delta in cols .schema.optionQuote; "optionQuote has delta"];
  assert[`gamma in cols .schema.optionQuote; "optionQuote has gamma"];

  / Test optionPosition table exists and is keyed
  assert[`optionPosition in tables `.schema; "optionPosition table exists"];
  assert[`contractId in cols key .schema.optionPosition; "optionPosition keyed by contractId"];
 };

// ============================================================================
// CONTRACT ID VALIDATION TESTS
// ============================================================================

test_optionContractIdValidation:{[]
  -1 "Testing contract ID validation...";

  / Valid contract IDs
  assert[.schema.isValidOptionContractId[`AAPL250117C00150000]; "Valid call contract ID"];
  assert[.schema.isValidOptionContractId[`TSLA250221P00200000]; "Valid put contract ID"];
  assert[.schema.isValidOptionContractId[`SPY240315C00400000]; "Valid SPY contract ID"];

  / Invalid contract IDs
  assert[not .schema.isValidOptionContractId[`]; "Empty symbol is invalid"];
  assert[not .schema.isValidOptionContractId[`AAPL]; "Equity symbol is invalid"];
  assert[not .schema.isValidOptionContractId[`AAPL250117]; "Incomplete contract ID"];
  assert[not .schema.isValidOptionContractId[`AAPL250117X00150000]; "Invalid option type"];

  / isOption helper
  assert[.schema.isOption[`AAPL250117C00150000]; "isOption identifies valid contract"];
  assert[not .schema.isOption[`AAPL]; "isOption rejects equity symbol"];
 };

// ============================================================================
// INSERT AND QUERY TESTS
// ============================================================================

test_optionInsertAndQuery:{[]
  -1 "Testing insert and query operations...";

  / Clear tables
  delete from `.schema.optionContract;
  delete from `.schema.optionQuote;
  delete from `.schema.optionPosition;

  / Insert test contract
  `.schema.optionContract upsert ([]
    contractId:enlist `AAPL250117C00150000;
    underlying:enlist `AAPL;
    expiry:enlist 2025.01.17;
    strike:enlist 150000000j;  / $150.00 in fixed-precision
    optionType:enlist `call;
    style:enlist `american;
    multiplier:enlist 100j;
    status:enlist `active
  );

  / Test query
  contracts:0!select from .schema.optionContract where contractId=`AAPL250117C00150000;
  assert[1 = count contracts; "Contract inserted successfully"];
  assert[`AAPL = first contracts`underlying; "Underlying symbol correct"];
  assert[150000000j = first contracts`strike; "Strike price correct (fixed-precision)"];

  / Insert test quote
  `.schema.optionQuote insert (
    .z.p;                    / timestamp
    `AAPL250117C00150000;    / contractId
    5500000j;                / bidPrice ($5.50)
    5600000j;                / askPrice ($5.60)
    100j;                    / bidSize
    150j;                    / askSize
    0.25;                    / impliedVol (25%)
    0.55;                    / delta
    0.05;                    / gamma
    -0.03;                   / theta
    0.15;                    / vega
    0.02;                    / rho
    150500000j               / underlyingPrice ($150.50)
  );

  / Test quote query
  quotes:select from .schema.optionQuote where contractId=`AAPL250117C00150000;
  assert[1 = count quotes; "Quote inserted successfully"];
  assert[5500000j = first quotes`bidPrice; "Bid price correct"];
  assert[0.25 = first quotes`impliedVol; "Implied vol correct"];

  / Insert test position
  `.schema.optionPosition upsert ([]
    contractId:enlist `AAPL250117C00150000;
    underlying:enlist `AAPL;
    expiry:enlist 2025.01.17;
    strike:enlist 150000000j;
    optionType:enlist `call;
    quantity:enlist 10j;
    avgEntryPrice:enlist 5500000j;
    marketValue:enlist 56000000j;
    unrealizedPnL:enlist 500000j;
    delta:enlist 5.5;
    gamma:enlist 0.5;
    theta:enlist -0.3;
    vega:enlist 1.5;
    side:enlist `long;
    marginUsed:enlist 55000000j;
    updatedAt:enlist .z.p
  );

  / Test position query (keyed table)
  position:.schema.optionPosition[`AAPL250117C00150000];
  assert[not ()~position; "Position inserted successfully"];
  assert[10j = position`quantity; "Position quantity correct"];
  assert[`long = position`side; "Position side correct"];
 };

// ============================================================================
// FIXED-PRECISION TESTS
// ============================================================================

test_optionFixedPrecision:{[]
  -1 "Testing fixed-precision price handling...";

  / Test strike prices (6 decimal places)
  strike100:100000000j;    / $100.00
  strike150_50:150500000j; / $150.50
  strike200_25:200250000j; / $200.25

  assert[strike100 = 100.0 * 1000000; "Strike $100.00 in fixed-precision"];
  assert[strike150_50 = 150.5 * 1000000; "Strike $150.50 in fixed-precision"];
  assert[strike200_25 = 200.25 * 1000000; "Strike $200.25 in fixed-precision"];

  / Test premium prices
  premium5_50:5500000j;    / $5.50
  premium0_25:250000j;     / $0.25

  assert[premium5_50 = 5.5 * 1000000; "Premium $5.50 in fixed-precision"];
  assert[premium0_25 = 0.25 * 1000000; "Premium $0.25 in fixed-precision"];

  / Test conversion back to float
  assert[100.0 = strike100 % 1000000.0; "Convert strike back to float"];
  assert[5.5 = premium5_50 % 1000000.0; "Convert premium back to float"];
 };

-1 "Options schema tests loaded";
if[not `medusaRunAll in key `.; exit .test.run[`.]];
