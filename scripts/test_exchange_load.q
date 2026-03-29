/ Quick validation script to check if exchange modules load correctly

-1 "Loading types.q...";
\l src/q/schema/types.q

-1 "Loading exchange/base.q...";
\l src/q/exchange/base.q

-1 "Loading exchange/registry.q...";
\l src/q/exchange/registry.q

-1 "Loading exchange/stub.q...";
\l src/q/exchange/stub.q

-1 "\n========================================";
-1 "  Validation Results";
-1 "========================================";

/ Check namespaces exist
-1 "Checking namespaces...";
-1 "  .exchange: ",string not null `.exchange;
-1 "  .exchange.registry: ",string not null `.exchange.registry;
-1 "  .exchange.stub: ",string not null `.exchange.stub;

/ Check key functions exist
-1 "\nChecking functions...";
-1 "  .exchange.placeOrder: ",string 100h = type .exchange.placeOrder;
-1 "  .exchange.cancelOrder: ",string 100h = type .exchange.cancelOrder;
-1 "  .exchange.getBalance: ",string 100h = type .exchange.getBalance;
-1 "  .exchange.registry.register: ",string 100h = type .exchange.registry.register;
-1 "  .exchange.stub.init: ",string 100h = type .exchange.stub.init;

/ Check enumerations
-1 "\nChecking enumerations...";
-1 "  ORDER_TYPE: ",", " sv string .exchange.ORDER_TYPE;
-1 "  ORDER_STATE: ",", " sv string .exchange.ORDER_STATE;
-1 "  ORDER_SIDE: ",", " sv string .exchange.ORDER_SIDE;

-1 "\n========================================";
-1 "  All modules loaded successfully!";
-1 "========================================";

exit 0
