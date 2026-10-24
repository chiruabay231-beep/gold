/* ICT Killzones + Pivots, FVG / volume imbalances, market structure and the shark
 * money flow: the same rules as the app (BacktestKit KillzonePivots / SharkFlow),
 * on bars {time (s, UTC), open, high, low, close, volume}. Everything is returned
 * in bar indexes; the chart layer turns them into pixels. */
(() => {
  "use strict";

  const ZONE = "America/New_York";
  const SESSIONS = [
    { name: "Asia", start: 20, end: 24, hi: "AS.H", lo: "AS.L", color: "#2962ff" },
    { name: "London", start: 2, end: 5, hi: "LO.H", lo: "LO.L", color: "#f23645" },
    { name: "NY AM", start: 9.5, end: 11, hi: "NYAM.H", lo: "NYAM.L", color: "#089981" },
    { name: "NY Lunch", start: 12, end: 13, hi: "NYL.H", lo: "NYL.L", color: "#fabf00" },
    { name: "NY PM", start: 13.5, end: 16, hi: "NYPM.H", lo: "NYPM.L", color: "#9c27b0" },
  ];
  const OPENS = [{ hour: 0, label: "DO" }, { hour: 9.5, label: "09:30" }];
  const MACROS = [
    [2 + 33 / 60, 3], [4 + 3 / 60, 4.5], [8 + 50 / 60, 9 + 10 / 60], [9 + 50 / 60, 10 + 10 / 60],
    [10 + 50 / 60, 11 + 10 / 60], [11 + 50 / 60, 12 + 10 / 60], [13 + 10 / 60, 13 + 40 / 60], [15.25, 15.75],
  ];
  const MAX_DAYS = 3;

  // New York offset per hour bucket (DST changes on the hour).
  const offsetCache = new Map();
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: ZONE, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
  });
  function offsetSeconds(t) {
    const bucket = Math.floor(t / 3600);
    let o = offsetCache.get(bucket);
    if (o === undefined) {
      const p = Object.fromEntries(parts.formatToParts(new Date(bucket * 3600 * 1000)).map((x) => [x.type, x.value]));
      const local = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24, +p.minute) / 1000;
      o = local - bucket * 3600;
      offsetCache.set(bucket, o);
    }
    return o;
  }

  /** Hour of day, day number and week number in New York for each bar. */
  function clock(bars) {
    const hour = new Array(bars.length), day = new Array(bars.length), week = new Array(bars.length);
    bars.forEach((b, i) => {
      const local = b.time + offsetSeconds(b.time);
      const d = Math.floor(local / 86400);
      day[i] = d;
      week[i] = Math.floor((d + 4) / 7);
      hour[i] = (local - d * 86400) / 3600;
    });
    return { hour, day, week };
  }

  function windows(ck, start, end) {
    const out = [];
    let first = null;
    for (let i = 0; i < ck.hour.length; i++) {
      const h = ck.hour[i];
      const inside = start <= end ? h >= start && h < end : h >= start || h < end;
      if (inside) { if (first === null) first = i; } else if (first !== null) { out.push([first, i - 1]); first = null; }
    }
    if (first !== null) out.push([first, ck.hour.length - 1]);
    return out;
  }

  function firstTouch(c, price, isHigh, from) {
    for (let j = from; j < c.length; j++) if (isHigh ? c[j].high >= price : c[j].low <= price) return j;
    return null;
  }
  function firstBreak(c, price, isHigh, from) {
    for (let j = from; j < c.length; j++) if (isHigh ? c[j].high > price : c[j].low < price) return j;
    return null;
  }

  function markIndexes(ck, hour, firstDay) {
    const out = [];
    let lastDay = -Infinity;
    for (let i = 1; i < ck.hour.length; i++) {
      if (ck.day[i] < firstDay || ck.day[i] === lastDay || ck.hour[i] < hour) continue;
      lastDay = ck.day[i];
      const crossedToday = ck.day[i - 1] === ck.day[i] && ck.hour[i - 1] < hour;
      const dayStartsAtMark = ck.day[i - 1] !== ck.day[i] && ck.hour[i] < hour + 1;
      if (crossedToday || dayStartsAtMark) out.push(i);
    }
    return out;
  }

  /* ---------- gaps ---------- */

  function rawGaps(c, displacement) {
    const n = c.length, gaps = [];
    if (n < 3) return gaps;
    const sums = [0];
    c.forEach((b) => sums.push(sums[sums.length - 1] + Math.abs(b.close - b.open)));
    const strong = (m, bull) => {
      if (displacement == null) return true;
      const b = c[m], body = Math.abs(b.close - b.open);
      if ((b.close > b.open) !== bull || body < (b.high - b.low) * 0.5) return false;
      const from = Math.max(0, m - 20);
      if (m <= from) return true;
      return body >= (sums[m] - sums[from]) / (m - from) * displacement;
    };
    for (let i = 2; i < n; i++) {
      if (c[i].low > c[i - 2].high && strong(i - 1, true)) {
        gaps.push({ bull: true, top: c[i].low, bottom: c[i - 2].high, start: i - 1, end: i - 1 });
      } else if (c[i].high < c[i - 2].low && strong(i - 1, false)) {
        gaps.push({ bull: false, top: c[i - 2].low, bottom: c[i].high, start: i - 1, end: i - 1 });
      }
    }
    return gaps;
  }

  function followed(raw, start, formed, c) {
    const g = Object.assign({}, raw, { start, end: c.length - 1, touched: false, filled: false });
    for (let j = formed + 1; j < c.length; j++) {
      if (raw.bull ? c[j].low <= raw.top : c[j].high >= raw.bottom) {
        g.touched = true;
        g.filled = raw.bull ? c[j].low <= raw.bottom : c[j].high >= raw.top;
        g.end = j;
        break;
      }
    }
    return g;
  }

  // A touched gap stays while price has not traded through it, for 15 minutes.
  function stillShown(g, c) {
    if (!g.touched || g.end >= c.length) return true;
    for (let j = g.end; j < c.length; j++) if (g.bull ? c[j].low < g.bottom : c[j].high > g.top) return false;
    return c[c.length - 1].time - c[g.end].time <= 15 * 60;
  }

  function higherTimeframe(sec) {
    return { 60: 300, 300: 900, 900: 3600, 1800: 14400, 3600: 14400, 14400: 86400, 86400: 604800 }[sec] || null;
  }

  function aggregate(c, seconds) {
    const shift = seconds >= 604800 ? 345600 : 0;
    const bars = [], first = [];
    let bucket = -Infinity;
    c.forEach((b, i) => {
      const k = Math.floor((b.time - shift) / seconds);
      if (k !== bucket) { bucket = k; bars.push(Object.assign({}, b)); first.push(i); } else {
        const l = bars[bars.length - 1];
        l.high = Math.max(l.high, b.high); l.low = Math.min(l.low, b.low); l.close = b.close;
      }
    });
    return { bars, first };
  }

  function fairValueGaps(c, sec) {
    const gaps = [];
    const raw = rawGaps(c, 1.5);
    for (let k = raw.length - 1; k >= 0 && gaps.length < 40; k--) {
      const g = followed(raw[k], raw[k].start, raw[k].start + 1, c);
      if (stillShown(g, c)) gaps.push(g);
    }
    gaps.reverse();
    const higher = higherTimeframe(sec);
    if (higher && gaps.length) {
      const { bars, first } = aggregate(c, higher);
      const earliest = gaps[0].start;
      const big = rawGaps(bars, null).map((r) => {
        const formed = r.start + 3 < first.length ? first[r.start + 3] - 1 : c.length - 1;
        return followed(r, first[r.start], formed, c);
      }).filter((h) => h.end >= earliest);
      gaps.forEach((g) => {
        g.confluence = big.some((h) => h.bull === g.bull && h.bottom < g.top && g.bottom < h.top && h.start <= g.end && g.start <= h.end);
      });
    }
    return gaps;
  }

  function volumeImbalances(c) {
    const n = c.length, out = [];
    if (n < 3) return out;
    const tail = c.slice(-100);
    const minimum = tail.reduce((a, b) => a + b.high - b.low, 0) / tail.length * 0.03;
    for (let i = n - 1; i >= 1 && out.length < 20; i--) {
      const a = c[i - 1], b = c[i];
      let raw = null;
      if (a.close > a.open && b.close > b.open && b.open - a.close > minimum && b.low <= a.high) {
        raw = { bull: true, top: b.open, bottom: a.close, start: i - 1, end: i - 1 };
      } else if (a.close < a.open && b.close < b.open && a.close - b.open > minimum && b.high >= a.low) {
        raw = { bull: false, top: a.close, bottom: b.open, start: i - 1, end: i - 1 };
      }
      if (!raw) continue;
      const g = followed(raw, i - 1, i, c);
      if (stillShown(g, c)) out.push(g);
    }
    return out.reverse();
  }

  function structureBreaks(c, length = 5) {
    const n = c.length, out = [];
    if (n <= length * 2 + 1) return out;
    let hi = null, lo = null, trend = 0;
    for (let i = 0; i < n; i++) {
      const p = i - length;
      if (p >= length) {
        let isHi = true, isLo = true;
        for (let j = p - length; j <= p + length; j++) {
          if (j === p) continue;
          if (c[j].high >= c[p].high) isHi = false;
          if (c[j].low <= c[p].low) isLo = false;
        }
        if (isHi) hi = { price: c[p].high, index: p };
        if (isLo) lo = { price: c[p].low, index: p };
      }
      if (hi && c[i].close > hi.price) {
        if (trend === -1) out.push({ bull: true, price: hi.price, start: hi.index, end: i });
        trend = 1; hi = null;
      }
      if (lo && c[i].close < lo.price) {
        if (trend === 1) out.push({ bull: false, price: lo.price, start: lo.index, end: i });
        trend = -1; lo = null;
      }
    }
    return out.slice(-20);
  }

  /* ---------- killzones ---------- */

  function compute(c, sec, show) {
    const out = { boxes: [], levels: [], stamps: [], macros: [], fvgs: [], vis: [], breaks: [], sweeps: [], hidden: false };
    if (c.length < 3) return out;
    if (show.fvg) { out.fvgs = fairValueGaps(c, sec); out.vis = volumeImbalances(c); }
    if (show.mss) out.breaks = structureBreaks(c);
    const ck = clock(c);
    const n = c.length;
    if (show.daily && sec < 86400) out.levels.push(...dailyLevels(c, ck));
    if (sec > 30 * 60) { out.hidden = show.killzones; return out; }
    if (!show.killzones) return out;
    const firstDay = ck.day[n - 1] - MAX_DAYS + 1;

    SESSIONS.forEach((s) => {
      for (const [a, b] of windows(ck, s.start, s.end)) {
        let high = -Infinity, low = Infinity, hiI = a, loI = a;
        for (let i = a; i <= b; i++) {
          if (c[i].high > high) { high = c[i].high; hiI = i; }
          if (c[i].low < low) { low = c[i].low; loI = i; }
        }
        if (ck.day[b] < firstDay) continue;
        out.boxes.push({ start: a, end: b, high, low, label: s.name, color: s.color });
        if (b >= n - 1) {
          // Still open: the running high/low.
          out.levels.push({ price: high, start: hiI, end: null, label: s.hi, color: s.color });
          out.levels.push({ price: low, start: loI, end: null, label: s.lo, color: s.color });
          continue;
        }
        for (const isHigh of [true, false]) {
          const price = isHigh ? high : low;
          const j = firstBreak(c, price, isHigh, b + 1);
          if (j !== null && (isHigh ? c[j].close < price : c[j].close > price)) {
            out.sweeps.push({ bull: !isHigh, price, index: j, label: isHigh ? s.hi : s.lo });
          }
          out.levels.push({ price, start: isHigh ? hiI : loI, end: j, label: isHigh ? s.hi : s.lo, color: s.color, mitigated: j !== null });
        }
      }
    });

    if (sec <= 15 * 60) {
      MACROS.forEach(([s, e]) => {
        for (const [a, b] of windows(ck, s, e)) {
          if (ck.day[b] < firstDay) continue;
          let high = -Infinity, low = Infinity;
          for (let i = a; i <= b; i++) { high = Math.max(high, c[i].high); low = Math.min(low, c[i].low); }
          const h = Math.floor(s), m = Math.round((s - h) * 60);
          out.macros.push({ start: a, end: b, high, low, label: `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}` });
        }
      });
    }

    OPENS.forEach((o) => {
      const starts = markIndexes(ck, o.hour, firstDay);
      starts.forEach((st, k) => {
        out.levels.push({ price: c[st].open, start: st, end: k + 1 < starts.length ? starts[k + 1] - 1 : null, label: o.label, color: "#787b86", open: true });
      });
    });
    out.stamps = markIndexes(ck, 0, firstDay);

    // Sweeps of the previous day's high and low.
    let start = n - 1;
    while (start > 0 && ck.day[start - 1] === ck.day[n - 1]) start--;
    if (start > 0) {
      const prev = ck.day[start - 1];
      let high = -Infinity, low = Infinity;
      for (let i = start - 1; i >= 0 && ck.day[i] === prev; i--) { high = Math.max(high, c[i].high); low = Math.min(low, c[i].low); }
      [[true, high, "PDH"], [false, low, "PDL"]].forEach(([isHigh, price, label]) => {
        const j = firstBreak(c, price, isHigh, start);
        if (j !== null && (isHigh ? c[j].close < price : c[j].close > price)) out.sweeps.push({ bull: !isHigh, price, index: j, label });
      });
    }
    out.sweeps = out.sweeps.sort((a, b) => a.index - b.index).slice(-20);
    return out;
  }

  // High and low of each of the last 5 finished days, until a candle reaches them.
  function dailyLevels(c, ck) {
    const n = c.length, today = ck.day[n - 1], ranges = [];
    let end = n - 1;
    while (end >= 0 && ck.day[end] === today) end--;
    while (end >= 0 && ranges.length < 5) {
      let start = end;
      while (start > 0 && ck.day[start - 1] === ck.day[end]) start--;
      ranges.push([start, end]);
      end = start - 1;
    }
    const levels = [];
    ranges.reverse().forEach(([a, b]) => {
      let hiI = a, loI = a;
      for (let i = a; i <= b; i++) { if (c[i].high > c[hiI].high) hiI = i; if (c[i].low < c[loI].low) loI = i; }
      [[true, hiI, c[hiI].high], [false, loI, c[loI].low]].forEach(([isHigh, st, price]) => {
        const touch = firstTouch(c, price, isHigh, b + 1);
        levels.push({ price, start: st, end: touch, label: "", color: isHigh ? "#089981" : "#f23645", mitigated: touch !== null, daily: true });
      });
    });
    return levels;
  }

  /* ---------- shark flow ---------- */

  function sharkFlow(c, length = 20) {
    const n = c.length;
    if (n <= length) return null;
    const useVolume = c.some((b) => b.volume > 0);
    const weight = c.map((b) => (useVolume ? b.volume : Math.max(b.high - b.low, 0)));
    const pressure = c.map((b) => { const r = b.high - b.low; return r > 0 ? ((b.close - b.low) - (b.high - b.close)) / r : 0; });
    let money = 0, total = 0;
    for (let i = n - length; i < n; i++) { money += pressure[i] * weight[i]; total += weight[i]; }
    const flow = total > 0 ? Math.max(-1, Math.min(1, money / total)) : 0;
    let range = 0;
    for (let i = n - length; i < n; i++) range += c[i].high - c[i].low;
    const change = c[n - 1].close - c[n - 1 - length].close;
    const threshold = range / length * 0.5;
    const situation = change > threshold ? (flow < -0.05 ? "weakUp" : "strongUp")
      : change < -threshold ? (flow > 0.05 ? "weakDown" : "strongDown") : "flat";
    // The newest shark bar of the last 30.
    let shark = null, sum = 0;
    for (let i = 0; i < n; i++) {
      if (i >= length) {
        const avg = sum / length, ratio = avg > 0 ? weight[i] / avg : 0;
        if (ratio >= 2.5 && Math.abs(pressure[i]) >= 0.33 && i >= n - 30) shark = { buying: pressure[i] > 0, ratio };
        sum -= weight[i - length];
      }
      sum += weight[i];
    }
    return { flow, situation, shark };
  }

  window.ICT = { compute, sharkFlow, offsetSeconds };
})();
