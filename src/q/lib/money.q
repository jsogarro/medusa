/ Medusa — Money and Currency Type System
/ Type-safe currency-aware money operations
/ Prevents currency confusion bugs (adding USD to BTC without conversion)

\d .money

/ ========================================
/ Phase 1: Currency Enumeration and Metadata
/ ========================================

/ Currency metadata table
/ Columns: currency (symbol), precision (int), symbol (string), name (string)
currencies: flip `currency`precision`symbol`name!(
  `BTC`USD`EUR`GBP`JPY`ETH`USDT;
  8 2 2 2 0 18 2;  / Decimal precision
  ("BTC";"$";"€";"£";"¥";"ETH";"USDT");
  ("Bitcoin";"US Dollar";"Euro";"British Pound";"Japanese Yen";"Ethereum";"Tether")
 );

/ Index by currency symbol for O(1) lookup
currencies: `currency xkey currencies;

/ Validate currency exists
/ @param c symbol - Currency code
/ @return boolean - 1b if valid, 0b otherwise
validCurrency:{[c]
  c in key currencies
 };

/ Throw error if currency invalid
/ @param c symbol - Currency code
requireCurrency:{[c]
  if[not validCurrency[c];
    '"Invalid currency: ",string c
  ];
 };

/ Get decimal precision for currency
/ @param c symbol - Currency code
/ @return int - Number of decimal places
precision:{[c]
  requireCurrency[c];
  currencies[c;`precision]
 };

/ ========================================
/ Phase 2: Money Type Constructor and Validation
/ ========================================

/ Round amount to currency precision
/ @param amt float - Raw amount
/ @param c symbol - Currency code
/ @return float - Rounded amount
round:{[amt;c]
  prec: precision[c];
  mult: 10 xexp prec;
  (floor 0.5 + amt * mult) % mult
 };

/ Create a Money value
/ @param amt number or string - Amount
/ @param c symbol - Currency code
/ @return dict - Money dictionary `amount`currency
new:{[amt;c]
  requireCurrency[c];

  / Parse string input if needed
  a: $[10h = type amt;  / String type
    "F"$amt;             / Parse to float
    amt
  ];

  / Validate amount
  if[not a >= 0;
    '"Amount must be non-negative: ",string a
  ];

  / Return rounded money dict
  `amount`currency!(round[a;c];c)
 };

/ Check if value is a Money dict
/ @param m any - Value to check
/ @return boolean
isMoney:{[m]
  (99h = type m) and (`amount`currency ~ key m) and validCurrency[m`currency]
 };

/ Require Money type or throw error
/ @param m any - Value to check
requireMoney:{[m]
  if[not isMoney[m];
    '"Expected Money dictionary, got: ",string type m
  ];
 };

/ ========================================
/ Phase 3: Money Arithmetic Operators
/ ========================================

/ Add two Money values
/ @param m1 dict - First money value
/ @param m2 dict - Second money value
/ @return dict - Sum in same currency
add:{[m1;m2]
  requireMoney each (m1;m2);

  / Cache dict access
  c1:m1`currency; a1:m1`amount;
  c2:m2`currency; a2:m2`amount;

  / Enforce same currency
  if[not c1 = c2;
    '"Currency mismatch: cannot add ",(string c1)," and ",string c2
  ];

  / Add amounts and round
  amt:round[a1 + a2; c1];
  `amount`currency!(amt;c1)
 };

/ Subtract two Money values
/ @param m1 dict - First money value
/ @param m2 dict - Second money value
/ @return dict - Difference in same currency
sub:{[m1;m2]
  requireMoney each (m1;m2);

  / Cache dict access
  c1:m1`currency; a1:m1`amount;
  c2:m2`currency; a2:m2`amount;

  if[not c1 = c2;
    '"Currency mismatch: cannot subtract ",(string c2)," from ",string c1
  ];

  / Subtract and round
  amt:round[a1 - a2; c1];

  / Allow negative results (useful for P&L calculations)
  `amount`currency!(amt;c1)
 };

/ Multiply Money by scalar
/ @param m dict - Money value
/ @param scalar float/long - Multiplier
/ @return dict - Product in same currency
mul:{[m;scalar]
  requireMoney[m];

  / Validate scalar is numeric
  if[not (type scalar) in -9 -8 -7 -6h;  / float, real, long, int
    '"Multiplier must be numeric, got: ",string type scalar
  ];

  / Check for null
  if[()~scalar; '"Multiplier cannot be null"];

  c: m`currency;
  amt: round[m[`amount] * scalar; c];
  `amount`currency!(amt;c)
 };

/ Divide Money by scalar
/ @param m dict - Money value
/ @param scalar float/long - Divisor
/ @return dict - Quotient in same currency
div:{[m;scalar]
  requireMoney[m];

  if[not (type scalar) in -9 -8 -7 -6h;
    '"Divisor must be numeric, got: ",string type scalar
  ];

  / Check for null
  if[()~scalar; '"Divisor cannot be null"];

  / Check for zero based on type
  if[(type scalar) in -9 -8h;  / float, real
    if[scalar = 0f; '"Division by zero"];
  ];
  if[(type scalar) in -7 -6h;  / long, int
    if[scalar = 0; '"Division by zero"];
  ];

  c: m`currency;
  amt: round[m[`amount] % scalar; c];
  `amount`currency!(amt;c)
 };

/ ========================================
/ Phase 4: Money Comparison Operators
/ ========================================

/ Check Money equality
/ @param m1 dict - First money value
/ @param m2 dict - Second money value
/ @return boolean - True if equal
eq:{[m1;m2]
  requireMoney each (m1;m2);

  / Must match currency AND amount
  (m1[`currency] = m2[`currency]) and (m1[`amount] = m2[`amount])
 };

/ Check if m1 < m2
/ @param m1 dict - First money value
/ @param m2 dict - Second money value
/ @return boolean - True if m1 < m2
lt:{[m1;m2]
  requireMoney each (m1;m2);

  if[not m1[`currency] = m2[`currency];
    '"Currency mismatch: cannot compare ",
     (string m1`currency)," and ",string m2`currency
  ];

  m1[`amount] < m2[`amount]
 };

/ Check if m1 > m2
/ @param m1 dict - First money value
/ @param m2 dict - Second money value
/ @return boolean - True if m1 > m2
gt:{[m1;m2]
  requireMoney each (m1;m2);

  if[not m1[`currency] = m2[`currency];
    '"Currency mismatch: cannot compare ",
     (string m1`currency)," and ",string m2`currency
  ];

  m1[`amount] > m2[`amount]
 };

/ Check if m1 <= m2
/ @param m1 dict - First money value
/ @param m2 dict - Second money value
/ @return boolean - True if m1 <= m2
lte:{[m1;m2]
  lt[m1;m2] or eq[m1;m2]
 };

/ Check if m1 >= m2
/ @param m1 dict - First money value
/ @param m2 dict - Second money value
/ @return boolean - True if m1 >= m2
gte:{[m1;m2]
  gt[m1;m2] or eq[m1;m2]
 };

/ ========================================
/ Phase 5: Money Formatting and Display
/ ========================================

/ Format amount to string with precision
/ @param amt float - Amount
/ @param prec int - Decimal places
/ @return string - Formatted amount
fmtAmount:{[amt;prec]
  / Build format string and use .Q.f for proper formatting
  .Q.f[prec;amt]
 };

/ Format Money value to string
/ @param m dict - Money value
/ @return string - Formatted string
fmt:{[m]
  requireMoney[m];

  c: m`currency;
  prec: precision[c];
  sym: currencies[c;`symbol];
  amt: fmtAmount[m`amount; prec];

  / Fiat currencies: symbol prefix ($100.50)
  / Crypto: amount + space + code (0.00500000 BTC)
  $[c in `USD`EUR`GBP`JPY;
    sym, amt;
    amt, " ", string c
  ]
 };

/ ========================================
/ Phase 6: Currency Conversion
/ ========================================

/ Forex rates table: (from, to, rate)
/ Rate = 1 unit of 'from' currency equals 'rate' units of 'to' currency
rates: flip `from`to`rate!(
  `USD`USD`EUR`EUR`BTC`BTC`USD`BTC`ETH`ETH`USD`EUR;
  `USD`EUR`USD`EUR`USD`ETH`BTC`ETH`USD`EUR`USD`GBP;
  1.0 0.855 1.17 1.0 50000.0 15.5 0.00002 3.1 3000.0 2565.0 1.0 0.73
 );

/ Index for fast lookup
rates: `from`to xkey rates;

/ Get forex rate from source to target currency
/ @param from symbol - Source currency
/ @param to symbol - Target currency
/ @return float - Exchange rate
getRate:{[from;to]
  / Same currency = 1:1
  if[from = to; :1.0];

  / Look up rate
  rate: rates[(from;to);`rate];

  / If not found, try inverse (check for null result)
  if[()~rate;
    invRate: rates[(to;from);`rate];
    if[()~invRate;
      '"No forex rate found for ",
       (string from)," to ",string to
    ];
    :1.0 % invRate
  ];

  rate
 };

/ Convert Money to target currency
/ @param m dict - Money value
/ @param targetCurrency symbol - Target currency code
/ @return dict - Money in target currency
convert:{[m;targetCurrency]
  requireMoney[m];
  requireCurrency[targetCurrency];

  / Get conversion rate
  rate: getRate[m`currency; targetCurrency];

  / Convert and round
  amt: round[m[`amount] * rate; targetCurrency];
  `amount`currency!(amt;targetCurrency)
 };

/ ========================================
/ Helper Functions
/ ========================================

/ Create zero money for a currency
/ @param c symbol - Currency code
/ @return dict - Money with zero amount
zero:{[c]
  new[0;c]
 };

/ Check if money is zero
/ @param m dict - Money value
/ @return boolean - True if amount is zero
isZero:{[m]
  requireMoney[m];
  m[`amount] = 0
 };

/ Get absolute value of money
/ @param m dict - Money value
/ @return dict - Money with absolute amount
abs:{[m]
  requireMoney[m];
  `amount`currency!((::) abs m`amount; m`currency)
 };

/ Negate money amount
/ @param m dict - Money value
/ @return dict - Money with negated amount
neg:{[m]
  requireMoney[m];
  `amount`currency!(neg m`amount; m`currency)
 };

\d .
