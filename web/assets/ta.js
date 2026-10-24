/* Standard indicators for the web chart (same formulas as BacktestKit's TA):
 * moving averages, Bollinger Bands, VWAP, Supertrend, volume, RSI, MACD,
 * Stochastic and ATR. Inputs are bars {time, open, high, low, close, volume};
 * outputs are arrays aligned with the bars (null before there is enough data). */
(() => {
  "use strict";

  const STUDIES = {
    ema: { name: "EMA (đường trung bình hàm mũ)", overlay: true, params: { length: 20, source: "close" }, colors: ["#ff9800"] },
    sma: { name: "SMA (đường trung bình)", overlay: true, params: { length: 50, source: "close" }, colors: ["#2962ff"] },
    bb: { name: "Bollinger Bands", overlay: true, params: { length: 20, mult: 2 }, colors: ["#2962ff", "#f23645", "#089981"] },
    vwap: { name: "VWAP (theo ngày)", overlay: true, params: {}, colors: ["#9c27b0"] },
    supertrend: { name: "Supertrend", overlay: true, params: { length: 10, mult: 3 }, colors: ["#089981", "#f23645"] },
    volume: { name: "Khối lượng", overlay: true, params: {}, colors: ["#089981", "#f23645"] },
    rsi: { name: "RSI", overlay: false, params: { length: 14, upper: 70, lower: 30 }, colors: ["#9c27b0"] },
    macd: { name: "MACD", overlay: false, params: { fast: 12, slow: 26, signal: 9 }, colors: ["#2962ff", "#ff9800", "#26a69a"] },
    stoch: { name: "Stochastic", overlay: false, params: { k: 14, d: 3, smooth: 3, upper: 80, lower: 20 }, colors: ["#2962ff", "#ff9800"] },
    atr: { name: "ATR", overlay: false, params: { length: 14 }, colors: ["#f23645"] },
  };

  const fade = (hex, a) => { const n = parseInt(hex.slice(1, 7), 16); return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`; };
  const src = (b, s) => (s === "open" ? b.open : s === "high" ? b.high : s === "low" ? b.low : s === "hl2" ? (b.high + b.low) / 2 : s === "hlc3" ? (b.high + b.low + b.close) / 3 : b.close);

  function sma(values, n) {
    const out = new Array(values.length).fill(null);
    let sum = 0, count = 0;
    for (let i = 0; i < values.length; i++) {
      const v = values[i];
      if (v == null) continue;
      sum += v; count++;
      if (i >= n && values[i - n] != null) { sum -= values[i - n]; count--; }
      if (count >= n) out[i] = sum / n;
    }
    return out;
  }

  function ema(values, n) {
    const out = new Array(values.length).fill(null);
    const k = 2 / (n + 1);
    let prev = null, seed = [], started = false;
    for (let i = 0; i < values.length; i++) {
      const v = values[i];
      if (v == null) continue;
      if (!started) {
        seed.push(v);
        if (seed.length === n) { prev = seed.reduce((a, b) => a + b, 0) / n; out[i] = prev; started = true; }
        continue;
      }
      prev = v * k + prev * (1 - k);
      out[i] = prev;
    }
    return out;
  }

  /** Wilder's smoothing (RSI, ATR). */
  function rma(values, n) {
    const out = new Array(values.length).fill(null);
    let prev = null, seed = [];
    for (let i = 0; i < values.length; i++) {
      const v = values[i];
      if (v == null) continue;
      if (prev == null) {
        seed.push(v);
        if (seed.length === n) { prev = seed.reduce((a, b) => a + b, 0) / n; out[i] = prev; }
        continue;
      }
      prev = (prev * (n - 1) + v) / n;
      out[i] = prev;
    }
    return out;
  }

  function trueRange(c) {
    return c.map((b, i) => (i === 0 ? b.high - b.low : Math.max(b.high - b.low, Math.abs(b.high - c[i - 1].close), Math.abs(b.low - c[i - 1].close))));
  }

  /** Lines (and histograms) of one study; each output is { kind: "line"|"hist", values, color, ... }. */
  function compute(type, c, p, colors, tzOffset) {
    const close = c.map((b) => b.close);
    switch (type) {
      case "ema": return [{ kind: "line", values: ema(c.map((b) => src(b, p.source)), p.length), color: colors[0] }];
      case "sma": return [{ kind: "line", values: sma(c.map((b) => src(b, p.source)), p.length), color: colors[0] }];
      case "bb": {
        const mid = sma(close, p.length);
        const up = [], lo = [];
        for (let i = 0; i < c.length; i++) {
          if (mid[i] == null) { up.push(null); lo.push(null); continue; }
          let v = 0;
          for (let j = i - p.length + 1; j <= i; j++) v += (close[j] - mid[i]) ** 2;
          const sd = Math.sqrt(v / p.length);
          up.push(mid[i] + p.mult * sd); lo.push(mid[i] - p.mult * sd);
        }
        return [{ kind: "line", values: mid, color: colors[0] }, { kind: "line", values: up, color: colors[1] }, { kind: "line", values: lo, color: colors[2] }];
      }
      case "vwap": {
        const out = [];
        let day = null, pv = 0, vol = 0;
        c.forEach((b) => {
          const d = Math.floor((b.time + (tzOffset || 0)) / 86400);
          if (d !== day) { day = d; pv = 0; vol = 0; }
          const v = b.volume || 1;
          pv += (b.high + b.low + b.close) / 3 * v; vol += v;
          out.push(pv / vol);
        });
        return [{ kind: "line", values: out, color: colors[0] }];
      }
      case "supertrend": {
        const atr = rma(trueRange(c), p.length);
        const up = [], dn = [];
        let trend = 1, upper = null, lower = null;
        for (let i = 0; i < c.length; i++) {
          if (atr[i] == null) { up.push(null); dn.push(null); continue; }
          const hl2 = (c[i].high + c[i].low) / 2;
          let u = hl2 + p.mult * atr[i], l = hl2 - p.mult * atr[i];
          if (upper != null && (u > upper && c[i - 1].close <= upper)) u = upper;
          if (lower != null && (l < lower && c[i - 1].close >= lower)) l = lower;
          if (upper != null && c[i].close > upper) trend = 1; else if (lower != null && c[i].close < lower) trend = -1;
          upper = u; lower = l;
          up.push(trend === 1 ? l : null); dn.push(trend === -1 ? u : null);
        }
        return [{ kind: "line", values: up, color: colors[0], width: 2 }, { kind: "line", values: dn, color: colors[1], width: 2 }];
      }
      case "volume":
        return [{ kind: "hist", values: c.map((b) => b.volume || 0), colorOf: (i) => fade(c[i].close >= c[i].open ? colors[0] : colors[1], 0.5), bottom: true }];
      case "rsi": {
        const gain = [], loss = [];
        c.forEach((b, i) => { const d = i ? b.close - c[i - 1].close : 0; gain.push(i ? Math.max(d, 0) : null); loss.push(i ? Math.max(-d, 0) : null); });
        const g = rma(gain, p.length), l = rma(loss, p.length);
        const out = g.map((v, i) => (v == null || l[i] == null ? null : l[i] === 0 ? 100 : 100 - 100 / (1 + v / l[i])));
        return [{ kind: "line", values: out, color: colors[0], levels: [p.upper, p.lower] }];
      }
      case "macd": {
        const f = ema(close, p.fast), s = ema(close, p.slow);
        const macd = f.map((v, i) => (v == null || s[i] == null ? null : v - s[i]));
        const signal = ema(macd, p.signal);
        const hist = macd.map((v, i) => (v == null || signal[i] == null ? null : v - signal[i]));
        return [{ kind: "hist", values: hist, colorOf: (i) => fade(hist[i] >= 0 ? colors[2] : "#ef5350", 0.7) },
          { kind: "line", values: macd, color: colors[0] }, { kind: "line", values: signal, color: colors[1] }];
      }
      case "stoch": {
        const raw = c.map((b, i) => {
          if (i < p.k - 1) return null;
          let hi = -Infinity, lo = Infinity;
          for (let j = i - p.k + 1; j <= i; j++) { hi = Math.max(hi, c[j].high); lo = Math.min(lo, c[j].low); }
          return hi === lo ? 50 : (b.close - lo) / (hi - lo) * 100;
        });
        const k = sma(raw, p.smooth), d = sma(k, p.d);
        return [{ kind: "line", values: k, color: colors[0], levels: [p.upper, p.lower] }, { kind: "line", values: d, color: colors[1] }];
      }
      case "atr": return [{ kind: "line", values: rma(trueRange(c), p.length), color: colors[0] }];
      default: return [];
    }
  }

  window.TA = { STUDIES, compute };
})();
