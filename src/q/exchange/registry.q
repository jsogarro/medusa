/ ============================================================================
/ registry.q - Exchange Implementation Registry
/ ============================================================================
/
/ Provides:
/   - Exchange implementation registration and dispatch
/   - Dictionary-based polymorphism for exchange operations
/   - Validation of implementation completeness
/
/ Dependencies:
/   - types.q (validation)
/
/ Functions:
/   - register: Register exchange implementation
/   - getImplementation: Retrieve implementation by exchange name
/   - listExchanges: List all registered exchanges
/   - isRegistered: Check if exchange is registered
/ ============================================================================

\d .exchange.registry

// ============================================================================
// REGISTRY STATE
// ============================================================================

/ Dictionary of registered exchange implementations
/ Key: exchangeName (symbol)
/ Value: implementation dict with functions
implementations:()!();

/ Required implementation functions
REQUIRED_FUNCTIONS:`placeOrder`cancelOrder`getBalance`getOrderbook`getOpenOrders`getPosition;

// ============================================================================
// IMPLEMENTATION VALIDATION
// ============================================================================

/ Validate implementation dict has all required functions
/ @param impl dict - Implementation dictionary
/ @return boolean - True if valid
validateImplementation:{[impl]
  / Check is dictionary
  if[not 99h = type impl;
    '"Implementation must be a dictionary"];

  / Check all required functions are present
  missingFunctions:REQUIRED_FUNCTIONS except key impl;
  if[count missingFunctions;
    '"Missing required functions: ",", " sv string missingFunctions];

  / Check all values are functions
  nonFunctions:where not (type each impl) in 100h;
  if[count nonFunctions;
    '"Non-function values for keys: ",", " sv string (key impl) nonFunctions];

  1b
 };

// ============================================================================
// REGISTRY FUNCTIONS
// ============================================================================

/ Register exchange implementation
/ @param exchangeName symbol - Exchange name
/ @param impl dict - Implementation dictionary with required functions
/ @return symbol - Exchange name (for chaining)
register:{[exchangeName;impl]
  / Validate exchange name
  if[not .qg.isValidExchange[exchangeName];
    '"Invalid exchange name: ",string exchangeName];

  / Validate implementation
  validateImplementation[impl];

  / Store implementation
  implementations[exchangeName]:impl;

  / Log registration
  -1 "  Registered exchange implementation: ",string exchangeName;

  exchangeName
 };

/ Get implementation for exchange
/ @param exchangeName symbol - Exchange name
/ @return dict - Implementation dictionary
getImplementation:{[exchangeName]
  if[not exchangeName in key implementations;
    '"Exchange not registered: ",string exchangeName];

  implementations[exchangeName]
 };

/ List all registered exchanges
/ @return symbol[] - List of registered exchange names
listExchanges:{[]
  key implementations
 };

/ Check if exchange is registered
/ @param exchangeName symbol - Exchange name
/ @return boolean - True if registered
isRegistered:{[exchangeName]
  exchangeName in key implementations
 };

/ Unregister exchange (for testing)
/ @param exchangeName symbol - Exchange name
unregister:{[exchangeName]
  implementations::enlist[exchangeName] _ implementations;
  exchangeName
 };

\d .

/ Export namespace
-1 "  Exchange registry loaded: .exchange.registry namespace";
