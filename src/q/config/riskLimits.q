/ ============================================================================
/ riskLimits.q - Configurable Risk Limits
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Loads risk limits from JSON config file and applies them to risk modules.
/ Replaces hardcoded limits throughout the risk system.
/ ----------------------------------------------------------------------------
/ Dependencies:
/   - risk/schema.q (risk state tables)
/   - lib/json.q (if using q's .j.k for JSON parsing)
/ ----------------------------------------------------------------------------
/ Usage:
/   .config.risk.loadLimits["configs/risk-limits.json"]
/   .config.risk.setLimit[`drawdown;`warnPct;7.5]
/ ============================================================================

\d .

/ ============================================================================
/ STATE
/ ============================================================================

/ Current risk limits (loaded from JSON)
limits:()!();

/ Path to the loaded config file
configPath:`;

/ ============================================================================
/ LOADING
/ ============================================================================

/ Load risk limits from JSON config file
/ @param path symbol - Path to JSON config file
/ @return boolean - 1b if successful
loadLimits:{[path]
  / Read JSON file
  jsonStr:@[read0;hsym path;{[e] -2 ("Failed to read config file: ",e); :()}];
  if[()~jsonStr; :0b];

  / Parse JSON (q's built-in .j.k)
  cfg:@[.j.k;raze jsonStr;{[e] -2 ("Failed to parse JSON: ",e); :()}];
  if[()~cfg; :0b];

  / Store config
  .config.risk.limits:cfg;
  .config.risk.configPath:path;

  / Apply to risk modules
  applyPositionLimits[cfg`positionLimits];
  applyDrawdownLimits[cfg`drawdown];
  applyRateLimits[cfg`rateLimit];
  applyConcentrationLimits[cfg`concentration];
  applyPDTLimits[cfg`pdt];
  applyMarginLimits[cfg`margin];
  applyGreeksLimits[cfg`greeks];
  applyMarketImpactLimits[cfg`marketImpact];

  -1 ("Risk limits loaded from: ",string path);
  1b
 };

/ ============================================================================
/ APPLY FUNCTIONS
/ ============================================================================

/ Apply position limits to .risk.globalPositionLimits
/ @param cfg dict - Position limits config
applyPositionLimits:{[cfg]
  / Set global limits (if table exists)
  if[`globalPositionLimits in key `.risk;
    / Store in risk module metadata
    .risk.globalPositionLimit:cfg`maxPositionSize;
    .risk.globalPositionPct:cfg`maxPositionPct;
  ];
 };

/ Apply drawdown limits to .risk.drawdownState
/ @param cfg dict - Drawdown config
applyDrawdownLimits:{[cfg]
  if[`drawdownState in key `.risk;
    / Update max drawdown in state table
    .risk.drawdownState[`maxDrawdownPct]:cfg`maxPct;
    .risk.drawdownWarnPct:cfg`warnPct;
    .risk.drawdownHaltPct:cfg`haltPct;
  ];
 };

/ Apply rate limits to .risk.rateLimits and .risk.globalRateLimits
/ @param cfg dict - Rate limit config (keyed by exchange)
applyRateLimits:{[cfg]
  if[`globalRateLimits in key `.risk;
    / Initialize rate limits for each exchange
    exchanges:key cfg;
    {[ex;limits]
      `.risk.globalRateLimits upsert (ex; limits`ordersPerSec; limits`burstCapacity; limits`burstCapacity; .z.p);
    }[;cfg] each exchanges;
  ];
 };

/ Apply concentration limits to .risk module
/ @param cfg dict - Concentration config
applyConcentrationLimits:{[cfg]
  .risk.maxExchangePct:cfg`maxExchangePct;
  .risk.maxAssetPct:cfg`maxAssetPct;
 };

/ Apply PDT limits to .risk.pdt module
/ @param cfg dict - PDT config
applyPDTLimits:{[cfg]
  .risk.pdtAccountMinimum:cfg`accountMinimum;
  .risk.pdtMaxDayTrades:cfg`maxDayTrades;
  .risk.pdtWindowDays:cfg`windowDays;
 };

/ Apply margin limits to .risk.margin module
/ @param cfg dict - Margin config
applyMarginLimits:{[cfg]
  .risk.regTInitialMargin:cfg`regTInitialMargin;
  .risk.regTMaintenanceMargin:cfg`regTMaintenanceMargin;
  .risk.portfolioMarginFactor:cfg`portfolioMarginFactor;
 };

/ Apply Greeks limits to .risk.greeksLimits module
/ @param cfg dict - Greeks config
applyGreeksLimits:{[cfg]
  .risk.maxDelta:cfg`maxDelta;
  .risk.maxGamma:cfg`maxGamma;
  .risk.maxVega:cfg`maxVega;
  .risk.maxTheta:cfg`maxTheta;
 };

/ Apply market impact limits to .risk.impactLimits
/ @param cfg dict - Market impact config
applyMarketImpactLimits:{[cfg]
  .risk.impactWarnPct:cfg`warnPct;
  .risk.impactRejectPct:cfg`rejectPct;
 };

/ ============================================================================
/ RUNTIME OVERRIDE
/ ============================================================================

/ Override a specific limit at runtime
/ @param category symbol - Limit category (`drawdown, `rateLimit, etc.)
/ @param param symbol - Parameter name
/ @param limitValue any - New value
setLimit:{[category;param;limitValue]
  / Update in-memory config
  if[not[category in key .config.risk.limits];
    -2 ("Unknown category: ",string category);
    :0b;
  ];
  categoryLimits:.config.risk.limits category;
  categoryLimits[param]:limitValue;
  .config.risk.limits[category]:categoryLimits;

  / Re-apply the specific category
  if[category~`positionLimits; applyPositionLimits[.config.risk.limits`positionLimits]];
  if[category~`drawdown; applyDrawdownLimits[.config.risk.limits`drawdown]];
  if[category~`rateLimit; applyRateLimits[.config.risk.limits`rateLimit]];
  if[category~`concentration; applyConcentrationLimits[.config.risk.limits`concentration]];
  if[category~`pdt; applyPDTLimits[.config.risk.limits`pdt]];
  if[category~`margin; applyMarginLimits[.config.risk.limits`margin]];
  if[category~`greeks; applyGreeksLimits[.config.risk.limits`greeks]];
  if[category~`marketImpact; applyMarketImpactLimits[.config.risk.limits`marketImpact]];

  -1 ("Updated ",string[category],".",string[param]," = ",.Q.s1 limitValue);
  1b
 };

/ Get current value of a limit
/ @param category symbol - Limit category
/ @param param symbol - Parameter name
/ @return any - Current value
getLimit:{[category;param]
  .config.risk.limits[category;param]
 };

set[`.config.risk.limits;limits];
set[`.config.risk.configPath;configPath];
set[`.config.risk.loadLimits;loadLimits];
set[`.config.risk.applyPositionLimits;applyPositionLimits];
set[`.config.risk.applyDrawdownLimits;applyDrawdownLimits];
set[`.config.risk.applyRateLimits;applyRateLimits];
set[`.config.risk.applyConcentrationLimits;applyConcentrationLimits];
set[`.config.risk.applyPDTLimits;applyPDTLimits];
set[`.config.risk.applyMarginLimits;applyMarginLimits];
set[`.config.risk.applyGreeksLimits;applyGreeksLimits];
set[`.config.risk.applyMarketImpactLimits;applyMarketImpactLimits];
set[`.config.risk.setLimit;setLimit];
set[`.config.risk.getLimit;getLimit];

\d .
