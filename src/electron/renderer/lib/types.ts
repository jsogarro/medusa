export interface Order {
  orderId: string;
  time: Date;
  strategy: string;
  exchange: string;
  pair: string;
  side: 'buy' | 'sell';
  orderType: 'market' | 'limit' | 'stop';
  price: number;
  quantity: number;
  filled: number;
  status: 'open' | 'filled' | 'cancelled' | 'rejected';
}

export interface Position {
  exchange: string;
  pair: string;
  quantity: number;
  avgPrice: number;
  unrealizedPnL: number;
  exposure: number;
}

export interface Trade {
  tradeId: string;
  orderId: string;
  time: Date;
  exchange: string;
  pair: string;
  side: 'buy' | 'sell';
  price: number;
  quantity: number;
  fee: number;
  realizedPnL: number;
}

export interface RiskMetrics {
  positionLimitUtilization: Record<string, number>;
  exposureUtilization: Record<string, number>;
  drawdownCurrent: number;
  drawdownMax: number;
  dailyVolumeUsed: number;
  dailyVolumeLimit: number;
}

export interface ExchangeStatus {
  exchange: string;
  connected: boolean;
  latency: number;
  errorCount: number;
  rateLimitUsed: number;
  rateLimitMax: number;
}

export interface Strategy {
  name: string;
  status: 'running' | 'paused' | 'stopped';
  trades: number;
  winRate: number;
  sharpe: number;
  pnl: number;
}

export interface Candlestick {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface VolumeSpike {
  time: Date;
  symbol: string;
  volume: number;
  avgVolume: number;
  spikeRatio: number;
  price: number;
  direction: 'buy' | 'sell';
}

export interface VwapData {
  time: number;
  price: number;
  vwap: number;
  upperBand: number;
  lowerBand: number;
  volume: number;
}

export interface VolumeLevelData {
  price: number;
  volume: number;
}

export interface CvdData {
  time: number;
  cvd: number;
  price: number;
}

export interface OrderFlowData {
  buyPressure: number;
  sellPressure: number;
  imbalance: number;
  history: Array<{ time: number; imbalance: number }>;
}

export interface Settings {
  connections: {
    tp: { host: string; port: number; connected: boolean };
    rdb: { host: string; port: number; connected: boolean };
    hdb: { host: string; port: number; connected: boolean };
  };
  exchanges: Array<{
    name: string;
    enabled: boolean;
    apiKey: string;
    rateLimit: number;
    status: 'connected' | 'disconnected';
  }>;
  riskLimits: {
    maxPositionSize: number;
    maxDailyVolume: number;
    maxDrawdownPct: number;
    maxExposurePerExchange: number;
    emergencyStopThreshold: number;
    circuitBreakerConsecutiveLosses: number;
    circuitBreakerPauseDuration: number;
  };
  display: {
    theme: 'dark';
    chartTimeframe: string;
    numberFormat: string;
    showExtendedHours: boolean;
    enableSoundAlerts: boolean;
  };
  paperMode: boolean;
}

export interface OptionQuote {
  strike: number;
  callBid: number;
  callAsk: number;
  callVol: number;
  callOI: number;
  callDelta: number;
  callIV: number;
  putBid: number;
  putAsk: number;
  putVol: number;
  putOI: number;
  putDelta: number;
  putIV: number;
  isATM: boolean;
  isITMCall: boolean;
  isITMPut: boolean;
}

export interface OptionPosition {
  symbol: string;
  strike: number;
  expiry: string;
  type: 'call' | 'put';
  quantity: number;
  avgPrice: number;
  delta: number;
  gamma: number;
  theta: number;
  vega: number;
  unrealizedPnL: number;
}

export interface PortfolioGreeks {
  totalDelta: number;
  totalGamma: number;
  totalTheta: number;
  totalVega: number;
  deltaLimit: number;
  gammaLimit: number;
  thetaLimit: number;
  vegaLimit: number;
  history: Array<{ time: number; delta: number; vega: number }>;
}

// Bond Trading types
export interface YieldCurvePoint {
  tenor: string;
  maturity: number; // in years
  rate: number; // in percentage
}

export interface YieldCurveSnapshot {
  label: string;
  color: string;
  points: YieldCurvePoint[];
}

export interface SpreadMetric {
  name: string;
  value: number; // in basis points
  change1D: number;
}

export interface RateChange {
  tenor: string;
  currentRate: number;
  change1D: number;
  change1W: number;
  change1M: number;
}

export interface DurationMetrics {
  modifiedDuration: number;
  dv01: number;
  convexity: number;
}

export interface KeyRateDuration {
  tenor: string;
  dv01: number;
}

export interface RateScenario {
  name: string;
  description: string;
  pnlImpact: number;
}

export interface BondHolding {
  cusip: string;
  maturity: string;
  coupon: number;
  ytm: number;
  faceValue: number;
  marketValue: number;
  duration: number;
}

export interface MaturityBucket {
  year: number;
  notional: number;
  holdings: BondHolding[];
}

export interface CashFlow {
  date: string;
  type: 'coupon' | 'maturity';
  cusip: string;
  amount: number;
}

// Algo execution types
export interface AlgoOrder {
  orderId: string;
  algoType: 'vwap' | 'twap' | 'iceberg';
  exchange: string;
  pair: string;
  side: 'buy' | 'sell';
  targetQty: number;
  filled: number;
  avgFillPrice: number;
  arrivalPrice: number;
  status: 'active' | 'paused' | 'completed' | 'cancelled';
  eta: string;
  duration?: string;
  childOrders?: Array<{
    orderId: string;
    time: string;
    qty: number;
    price: number;
    status: 'filled' | 'cancelled' | 'rejected';
  }>;
}
