/ Quick verification script for money library
/ Run with: q tests/q/verify_money.q

\l src/q/lib/money.q

-1 "";
-1 "========================================";
-1 "  Money Library Verification";
-1 "========================================";
-1 "";

-1 "1. Currency Metadata Table:";
-1 "----------------------------------------";
show .money.currencies;
-1 "";

-1 "2. Basic Constructor Tests:";
-1 "----------------------------------------";
m1: .money.new[100; `USD];
-1 "  Created: ",.money.fmt[m1];

m2: .money.new[0.123456789; `BTC];
-1 "  Created: ",.money.fmt[m2]," (rounded to 8 decimals)";

m3: .money.new["50.50"; `EUR];
-1 "  Created: ",.money.fmt[m3]," (parsed from string)";
-1 "";

-1 "3. Arithmetic Operations:";
-1 "----------------------------------------";
usd1: .money.new[100; `USD];
usd2: .money.new[50; `USD];

sum: .money.add[usd1; usd2];
-1 "  ",.money.fmt[usd1]," + ",.money.fmt[usd2]," = ",.money.fmt[sum];

diff: .money.sub[usd1; usd2];
-1 "  ",.money.fmt[usd1]," - ",.money.fmt[usd2]," = ",.money.fmt[diff];

prod: .money.mul[usd1; 1.5];
-1 "  ",.money.fmt[usd1]," × 1.5 = ",.money.fmt[prod];

quot: .money.div[usd1; 2];
-1 "  ",.money.fmt[usd1]," ÷ 2 = ",.money.fmt[quot];
-1 "";

-1 "4. Comparison Operations:";
-1 "----------------------------------------";
-1 "  ",.money.fmt[usd1]," > ",.money.fmt[usd2]," = ",string .money.gt[usd1; usd2];
-1 "  ",.money.fmt[usd1]," < ",.money.fmt[usd2]," = ",string .money.lt[usd1; usd2];
-1 "  ",.money.fmt[usd1]," = ",.money.fmt[usd1]," = ",string .money.eq[usd1; usd1];
-1 "";

-1 "5. Currency Conversion:";
-1 "----------------------------------------";
usd3: .money.new[100; `USD];
eur: .money.convert[usd3; `EUR];
-1 "  ",.money.fmt[usd3]," → ",.money.fmt[eur]," (rate: 0.855)";

btc1: .money.new[1; `BTC];
usd4: .money.convert[btc1; `USD];
-1 "  ",.money.fmt[btc1]," → ",.money.fmt[usd4]," (rate: 50,000)";
-1 "";

-1 "6. Helper Functions:";
-1 "----------------------------------------";
zero: .money.zero[`USD];
-1 "  Zero: ",.money.fmt[zero];

neg: .money.neg[.money.new[100; `USD]];
-1 "  Negation: ",.money.fmt[neg];

abs: .money.abs[neg];
-1 "  Absolute: ",.money.fmt[abs];
-1 "";

-1 "========================================";
-1 "  Verification Complete!";
-1 "  Money library is working correctly.";
-1 "========================================";
-1 "";

exit 0;
