/ ============================================================================
/ benchmark.q - Real-Time TCA Benchmark Calculation
/ ============================================================================
/ ----------------------------------------------------------------------------
/ Provides:
/   - Real-time VWAP, TWAP, and arrival price tracking
/   - Periodic benchmark updates via .z.ts timer
/   - Volatility calculation for timing risk estimation
/ ----------------------------------------------------------------------------
/ Functions:
/   - update: Calculate and store benchmarks for current interval
/   - benchmark.getBenchmark: Retrieve benchmark for specific time window
/   - getLatestBenchmark: Get most recent benchmark for pair
/ ============================================================================

\d .tca

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Benchmark benchmark.intervals (1min, 5min, 15min)
benchmark.intervals:`1min`5min`15min;

/ Interval durations in nanoseconds
benchmark.intervalDurations:`1min`5min`15min!60 300 900 * 1000000000j;

/ Last benchmark update timestamp
benchmark.lastUpdate:.z.p;

/ Update frequency (nanoseconds) - run every 60 seconds
benchmark.updateFrequency:60000000000j;

/ ============================================================================
/ BENCHMARK CALCULATION
/ ============================================================================

/ Calculate benchmarks for all active pairs
/ Called via .z.ts every 60 seconds
/ Performance target: <1ms per exchange-pair-interval combination
benchmark.update:{[]
  / Get current timestamp
  now:.z.p;

  / Check if enough time has elapsed since last update
  if[(now - benchmark.lastUpdate) < benchmark.updateFrequency; :()];

  / Update each interval
  {[now;intervalSym]
    / Get interval duration
    duration:benchmark.intervalDurations[intervalSym];
    startTime:now - duration;

    / Get trades in this interval from all exchanges
    / Query .qg.trade table for recent trades
    trades:select from .qg.trade where time_created within (startTime;now);

    / Validate data freshness (reject if oldest trade >60s old)
    maxAge:60000000000j; / 60 seconds in nanoseconds
    if[0 < count trades;
      oldestTimestamp:first exec time_created from trades;
      age:now - oldestTimestamp;
      if[age > maxAge;
        -1 "WARNING: TCA benchmark data is stale (oldest: ",string[oldestTimestamp],
           ", age: ",string[age % 1000000000]," seconds) - skipping interval ",string[intervalSym];
        :()
      ]
    ];

    / Group by exchange and pair (volume_currency + price_currency)
    / Note: Using volume_currency/price_currency columns from trade table
    grouped:select
      arrivalPx:first price,
      closePx:last price,
      totalVolume:sum volume,
      vwap:`long$(sum price * volume) % sum volume,
      twap:`long$avg price,
      priceList:price
      by exchange_name, pair:{`$string[x],string[y]}'[volume_currency;price_currency]
      from trades;

    / Guard against division by zero: replace null VWAP with long null.
    grouped:update vwap:?[totalVolume = 0; 0Nj; vwap] from grouped;

    / Calculate volatility (std dev of log returns)
    / Returns = log(price[i] / price[i-1])
    grouped:update volatility:{
      $[2 > count x;
        0f;  / Not enough data for volatility
        dev log ratios x  / ratios = x % prev x, then take log and std dev
      ]
    } each priceList
    from grouped;

    / Insert benchmarks into tcaBenchmark table
    {[now;intervalSym;row]
      / Skip if no valid VWAP (division by zero)
      if[null row`vwap; :()];

      / Insert benchmark row
      `.tca.tcaBenchmark insert (
        now;                        / time
        row`exchange_name;          / exchange
        row`pair;                   / pair
        intervalSym;                / interval
        row`arrivalPx;              / arrivalPx
        row`vwap;                   / vwap
        row`twap;                   / twap
        row`closePx;                / closePx
        row`totalVolume;            / volume
        row`volatility              / volatility
      );
    }[now;intervalSym] each 0!grouped;

  }[now] each benchmark.intervals;

  / Update last update timestamp
  benchmark.lastUpdate::now;

  -1 "  TCA benchmarks updated at ",string[now];
 };

/ Get benchmark for specific time window
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param intervalSym symbol - Interval (1min, 5min, 15min)
/ @param targetTime timestamp - Target time
/ @return dict - Benchmark values (vwap, twap, arrivalPx, volatility)
benchmark.getBenchmark:{[exchange;pair;intervalSym;targetTime]
  / Find benchmark closest to target time
  benchmarks:select from .tca.tcaBenchmark
    where exchange=exchange, pair=pair, interval=intervalSym, time <= targetTime;

  / Return most recent benchmark
  if[0 = count benchmarks; :`vwap`twap`arrivalPx`volatility!(0Nj;0Nj;0Nj;0n)];

  / Get last row
  lastBench:last benchmarks;

  `vwap`twap`arrivalPx`volatility!(
    lastBench`vwap;
    lastBench`twap;
    lastBench`arrivalPx;
    lastBench`volatility
  )
 };

/ Get latest benchmark for pair
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param intervalSym symbol - Interval
/ @return dict - Latest benchmark
benchmark.getLatestBenchmark:{[exchange;pair;intervalSym]
  benchmark.getBenchmark[exchange;pair;intervalSym;.z.p]
 };

/ Get benchmarks for time range (used in post-trade TCA)
/ @param exchange symbol - Exchange name
/ @param pair symbol - Trading pair
/ @param intervalSym symbol - Interval
/ @param startTime timestamp - Start of execution window
/ @param endTime timestamp - End of execution window
/ @return dict - Aggregated benchmarks (vwap, twap)
benchmark.getBenchmarksForWindow:{[exchange;pair;intervalSym;startTime;endTime]
  / Get all benchmarks in window
  benchmarks:select from .tca.tcaBenchmark
    where exchange=exchange, pair=pair, interval=intervalSym,
          time within (startTime;endTime);

  / If no benchmarks, return nulls
  if[0 = count benchmarks; :`vwap`twap!(0Nj;0Nj)];

  / Calculate window VWAP (volume-weighted across benchmark.intervals)
  / Guard against division by zero
  totalVol:sum benchmarks`volume;
  windowVwap:?[0 = totalVol; 0Nj; (sum benchmarks[`vwap] * benchmarks`volume) % totalVol];

  / Calculate window TWAP (simple average across benchmark.intervals)
  windowTwap:avg benchmarks`twap;

  `vwap`twap!(windowVwap;windowTwap)
 };

\d .

/ Export namespace
-1 "  TCA benchmark module loaded: .tca.benchmark namespace";
