/ ============================================================================
/ calendar.q - Market Hours and Trading Calendar
/ ============================================================================
/ // Provides:
/   - US equity market hours validation
/   - Trading day calendar (NYSE/NASDAQ)
/   - Holiday calendar (2026-2027)
/   - Extended hours support (pre-market, after-hours)
/ // Market Hours (US Eastern Time):
/   - Pre-market:   4:00 - 9:30 ET
/   - Regular:      9:30 - 16:00 ET
/   - After-hours: 16:00 - 20:00 ET
/ // Functions:
/   - isMarketOpen: Check if regular session is open now
/   - isTradingDay: Check if date is a trading day
/   - isExtendedHoursOpen: Check if extended hours are open now
/   - getNextTradingDay: Get next trading day
/   - getPrevTradingDay: Get previous trading day
/ ============================================================================

\d .exchange

// ============================================================================
// MARKET HOURS (US Eastern Time)
// ============================================================================

/ Regular session hours (9:30 - 16:00 ET)
calendar.REGULAR_OPEN_HOUR:9;
calendar.REGULAR_OPEN_MINUTE:30;
calendar.REGULAR_CLOSE_HOUR:16;
calendar.REGULAR_CLOSE_MINUTE:0;

/ Pre-market hours (4:00 - 9:30 ET)
calendar.PREMARKET_OPEN_HOUR:4;
calendar.PREMARKET_OPEN_MINUTE:0;
calendar.PREMARKET_CLOSE_HOUR:9;
calendar.PREMARKET_CLOSE_MINUTE:30;

/ After-hours (16:00 - 20:00 ET)
calendar.AFTERHOURS_OPEN_HOUR:16;
calendar.AFTERHOURS_OPEN_MINUTE:0;
calendar.AFTERHOURS_CLOSE_HOUR:20;
calendar.AFTERHOURS_CLOSE_MINUTE:0;

/ Eastern Time offset from UTC (hours)
/ Note: Adjust for DST (second Sunday in March - first Sunday in November)
calendar.ET_OFFSET_STANDARD:-5;   / EST (winter)
calendar.ET_OFFSET_DST:-4;        / EDT (summer)

// ============================================================================
// HOLIDAY CALENDAR (NYSE/NASDAQ)
// ============================================================================

/ US market holidays for 2026-2027
/ Format: date list
calendar.HOLIDAYS:(
  2026.01.01;  / New Year's Day
  2026.01.19;  / Martin Luther King Jr. Day
  2026.02.16;  / Presidents' Day
  2026.04.03;  / Good Friday
  2026.05.25;  / Memorial Day
  2026.07.03;  / Independence Day (observed, 7/4 is Saturday)
  2026.09.07;  / Labor Day
  2026.11.26;  / Thanksgiving
  2026.12.25;  / Christmas

  2027.01.01;  / New Year's Day
  2027.01.18;  / Martin Luther King Jr. Day
  2027.02.15;  / Presidents' Day
  2027.03.26;  / Good Friday
  2027.05.31;  / Memorial Day
  2027.07.05;  / Independence Day (observed, 7/4 is Sunday)
  2027.09.06;  / Labor Day
  2027.11.25;  / Thanksgiving
  2027.12.24   / Christmas (observed, 12/25 is Saturday)
 );

/ Early close days (close at 1:00 PM ET)
/ Day before Thanksgiving, Christmas Eve (if weekday), etc.
calendar.EARLY_CLOSE_DAYS:(
  2026.11.27;  / Day after Thanksgiving
  2026.12.24;  / Christmas Eve

  2027.11.26;  / Day after Thanksgiving
  2027.12.23   / Day before Christmas (observed)
 );

// ============================================================================
// TIMEZONE HELPERS
// ============================================================================

/ Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
/ q date epoch is 2000.01.01 (Saturday)
/ @param dt date - Date to check
/ @return int - Day of week (0-6)
calendar.getDayOfWeek:{[dt]
  (`int$dt + 6) mod 7  / Adjust for epoch (2000.01.01 was Saturday)
 };

/ Check if date is in DST period
/ DST: second Sunday in March - first Sunday in November
/ @param dt date - Date to check
/ @return boolean - True if in DST period
calendar.isDST:{[dt]
  year:`year$dt;

  / DST starts second Sunday in March
  marchFirst:year.03.01;
  marchFirstDow:calendar.getDayOfWeek[marchFirst];
  daysToFirstSunday:(7 - marchFirstDow) mod 7;
  firstSunday:marchFirst + daysToFirstSunday;
  secondSunday:firstSunday + 7;

  / DST ends first Sunday in November
  novFirst:year.11.01;
  novFirstDow:calendar.getDayOfWeek[novFirst];
  daysToFirstSunday:(7 - novFirstDow) mod 7;
  novFirstSunday:novFirst + daysToFirstSunday;

  / Check if date is between second Sunday in March and first Sunday in November
  (dt >= secondSunday) and (dt < novFirstSunday)
 };

/ Get current ET offset
/ @param dt date - Date to check
/ @return int - Hours offset from UTC
calendar.getETOffset:{[dt]
  $[calendar.isDST[dt]; calendar.ET_OFFSET_DST; calendar.ET_OFFSET_STANDARD]
 };

/ Convert UTC timestamp to ET
/ @param ts timestamp - UTC timestamp
/ @return timestamp - ET timestamp
calendar.utcToET:{[ts]
  dt:`date$ts;
  offset:calendar.getETOffset[dt];
  ts + offset*60*60*1000000000  / Offset in nanoseconds
 };

/ Get current ET time
/ @return timestamp - Current ET timestamp
calendar.currentET:{[]
  calendar.utcToET[.z.p]
 };

// ============================================================================
// TRADING DAY VALIDATION
// ============================================================================

/ Check if date is a weekday (Mon-Fri)
/ @param dt date - Date to check
/ @return boolean - True if weekday
calendar.isWeekday:{[dt]
  / q dates are integer days since 2000.01.01 which was a Saturday,
  / so (date mod 7) gives 0=Sat, 1=Sun, 2=Mon, ..., 6=Fri.
  dow:`int$dt mod 7;
  dow in 2 3 4 5 6    / Mon-Fri
 };

/ Check if date is a holiday
/ @param dt date - Date to check
/ @return boolean - True if holiday
calendar.isHoliday:{[dt]
  dt in calendar.HOLIDAYS
 };

/ Check if date is a trading day (weekday and not holiday)
/ @param dt date - Date to check
/ @return boolean - True if trading day
calendar.isTradingDay:{[dt]
  calendar.isWeekday[dt] and not calendar.isHoliday[dt]
 };

/ Check if today is a trading day
/ @return boolean - True if today is a trading day
calendar.isTodayTradingDay:{[]
  calendar.isTradingDay[`date$.z.d]
 };

// ============================================================================
// MARKET HOURS VALIDATION
// ============================================================================

/ Check if regular session is open now
/ @return boolean - True if market is open
calendar.isMarketOpen:{[]
  / Get current ET time
  et:calendar.currentET[];
  dt:`date$et;
  hh:`hh$et;
  mm:`mm$et;

  / Check if trading day
  if[not calendar.isTradingDay[dt]; :0b];

  / Check if within regular hours (9:30 - 16:00 ET)
  / Open: 9:30 or later
  openCheck:(hh > calendar.REGULAR_OPEN_HOUR) or (hh = calendar.REGULAR_OPEN_HOUR) and (mm >= calendar.REGULAR_OPEN_MINUTE);

  / Close: before 16:00
  closeCheck:(hh < calendar.REGULAR_CLOSE_HOUR) or (hh = calendar.REGULAR_CLOSE_HOUR) and (mm < calendar.REGULAR_CLOSE_MINUTE);

  openCheck and closeCheck
 };

/ Check if extended hours are open now (pre-market or after-hours)
/ @return boolean - True if extended hours are open
calendar.isExtendedHoursOpen:{[]
  / Get current ET time
  et:calendar.currentET[];
  dt:`date$et;
  hh:`hh$et;
  mm:`mm$et;

  / Check if trading day
  if[not calendar.isTradingDay[dt]; :0b];

  / Pre-market: 4:00 - 9:30
  preMarket:(hh >= calendar.PREMARKET_OPEN_HOUR) and (
    (hh < calendar.PREMARKET_CLOSE_HOUR) or
    (hh = calendar.PREMARKET_CLOSE_HOUR) and (mm < calendar.PREMARKET_CLOSE_MINUTE)
  );

  / After-hours: 16:00 - 20:00
  afterHours:(hh >= calendar.AFTERHOURS_OPEN_HOUR) and (
    (hh < calendar.AFTERHOURS_CLOSE_HOUR) or
    (hh = calendar.AFTERHOURS_CLOSE_HOUR) and (mm < calendar.AFTERHOURS_CLOSE_MINUTE)
  );

  preMarket or afterHours
 };

/ Check if date has early close (1:00 PM ET)
/ @param dt date - Date to check
/ @return boolean - True if early close day
calendar.isEarlyClose:{[dt]
  dt in calendar.EARLY_CLOSE_DAYS
 };

// ============================================================================
// TRADING DAY NAVIGATION
// ============================================================================

/ Get next trading day after given date
/ @param dt date - Starting date
/ @return date - Next trading day
calendar.getNextTradingDay:{[dt]
  / Start with next calendar day
  nextDay:dt + 1;

  / Keep advancing until we find a trading day
  while[not calendar.isTradingDay[nextDay]; nextDay+:1];

  nextDay
 };

/ Get previous trading day before given date
/ @param dt date - Starting date
/ @return date - Previous trading day
calendar.getPrevTradingDay:{[dt]
  / Start with previous calendar day
  prevDay:dt - 1;

  / Keep going back until we find a trading day
  while[not calendar.isTradingDay[prevDay]; prevDay-:1];

  prevDay
 };

/ Get next trading day from today
/ @return date - Next trading day
calendar.getNextTradingDayFromToday:{[]
  calendar.getNextTradingDay[`date$.z.d]
 };

/ Get previous trading day from today
/ @return date - Previous trading day
calendar.getPrevTradingDayFromToday:{[]
  calendar.getPrevTradingDay[`date$.z.d]
 };

\d .

/ Export namespace
-1 "  Market calendar loaded: .exchange.calendar namespace with US equity market hours";
