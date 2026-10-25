/* ICT Killzones + Pivots, FVG / volume imbalances, market structure, liquidity
 * sweeps and the shark money flow: the same rules and options as the app
 * (BacktestKit KillzonePivots / SharkFlow), on bars {time (s, UTC), open, high,
 * low, close, volume}. compute() returns everything in bar indexes; draw() paints
 * it inside the chart's own render pass (a lightweight-charts series primitive),
 * so it moves with the chart without lag. */
(() => {
  "use strict";

  function defaults() {
    return {
      timeZone: "America/New_York",
      tfLimit: 30, maxDays: 3,
      sessions: [
        { on: true, name: "Asia", start: 20, end: 24, hi: "AS.H", lo: "AS.L", color: "#2962ff" },
        { on: true, name: "London", start: 2, end: 5, hi: "LO.H", lo: "LO.L", color: "#f23645" },
        { on: true, name: "NY AM", start: 9.5, end: 11, hi: "NYAM.H", lo: "NYAM.L", color: "#089981" },
        { on: true, name: "NY Lunch", start: 12, end: 13, hi: "NYL.H", lo: "NYL.L", color: "#fabf00" },
        { on: true, name: "NY PM", start: 13.5, end: 16, hi: "NYPM.H", lo: "NYPM.L", color: "#9c27b0" },
      ],
      showBoxes: true, boxLabels: true, boxBorder: true, boxOpacity: 12,
      showPivots: true, pivotLabels: true, livePivots: true, pivotUntilMitigated: true, keepMitigated: true,
      // 2: levels broken by a candle stay, ending at that candle (older saves are moved onto it).
      keepVersion: 2, periodUntilBroken: true,
      pivotStyle: "solid", mitigatedStyle: "solid", midpoints: false, pivotWidth: 1,
      opens: [
        { on: true, hour: 0, label: "DO", color: "#787b86" },
        { on: false, hour: 8.5, label: "08:30", color: "#787b86" },
        { on: true, hour: 9.5, label: "09:30", color: "#787b86" },
        { on: false, hour: 13.5, label: "13:30", color: "#787b86" },
      ],
      openStyle: "dashed",
      stamps: [{ on: true, hour: 0 }, { on: false, hour: 8.5 }, { on: false, hour: 10 }, { on: false, hour: 14 }],
      stampColor: "#787b86", stampStyle: "dotted",
      cutoff: false, cutoffHour: 15,
      daily: true, dailyDays: 5, dailyKeepTouched: true, dayHighColor: "#089981", dayLowColor: "#f23645", dailyStyle: "solid",
      prevDay: false, prevWeek: false, prevMonth: false, periodColor: "#787b86",
      dayOfWeek: false, rangeTable: false, rangeAvg: 5,
      macros: true, macroTfLimit: 15, macroTimeLabels: true, macroColor: "#787b86",
      macroList: [
        { on: true, name: "London 1", start: 2 + 33 / 60, end: 3 },
        { on: true, name: "London 2", start: 4 + 3 / 60, end: 4.5 },
        { on: true, name: "NY AM 1", start: 8 + 50 / 60, end: 9 + 10 / 60 },
        { on: true, name: "NY AM 2", start: 9 + 50 / 60, end: 10 + 10 / 60 },
        { on: true, name: "NY AM 3", start: 10 + 50 / 60, end: 11 + 10 / 60 },
        { on: true, name: "NY Lunch", start: 11 + 50 / 60, end: 12 + 10 / 60 },
        { on: true, name: "NY PM", start: 13 + 10 / 60, end: 13 + 40 / 60 },
        { on: true, name: "Last Hour", start: 15.25, end: 15.75 },
      ],
      fvg: true, fvgFrom: 1, fvgTo: 1440, fvgStrong: true, fvgDisplacement: 1.5, fvgConfluence: true,
      fvgMid: true, fvgHideFilled: false, gapKeep: 15, fvgMinSize: 0, fvgCount: 40,
      fvgBull: "#089981", fvgBear: "#f23645", fvgZone: "#8c8f99", fvgZoneMid: "#9c27b0",
      vi: true, viCount: 20, viHideTouched: false, viColor: "#fa9900",
      mss: true, bos: false, swing: 5, structureCount: 20, mssBull: "#089981", mssBear: "#f23645",
      sweeps: true, sweepCount: 20, sweepColor: "#fa9900",
      lineScale: 1,
      // SMT against a related market (silver for gold): empty symbol = automatic.
      smtSymbol: "", smtInverse: false, smtSwing: 3, smtLookback: 60, smtCount: 10, smtBull: "#089981", smtBear: "#f23645",
    };
  }

  /** Saved settings over the defaults (keys added later keep their defaults). */
  function merge(saved) {
    const d = defaults();
    if (!saved || typeof saved !== "object") return d;
    for (const k of Object.keys(d)) {
      if (!(k in saved)) continue;
      if (Array.isArray(d[k])) {
        if (Array.isArray(saved[k])) d[k] = d[k].map((item, i) => Object.assign({}, item, saved[k][i] || {}));
      } else if (typeof saved[k] === typeof d[k]) d[k] = saved[k];
    }
    if (saved.keepVersion !== 2) {
      d.keepMitigated = true; d.pivotUntilMitigated = true; d.dailyKeepTouched = true; d.periodUntilBroken = true;
      d.keepVersion = 2;
    }
    return d;
  }

  /* ---------- clock in the indicator's time zone ---------- */

  const formats = new Map();
  const offsets = new Map();
  function offsetSeconds(t, zone) {
    const key = zone + ":" + Math.floor(t / 3600);
    let o = offsets.get(key);
    if (o === undefined) {
      let f = formats.get(zone);
      if (!f) {
        f = new Intl.DateTimeFormat("en-US", { timeZone: zone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
        formats.set(zone, f);
      }
      const at = Math.floor(t / 3600) * 3600;
      const p = Object.fromEntries(f.formatToParts(new Date(at * 1000)).map((x) => [x.type, x.value]));
      o = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24, +p.minute) / 1000 - at;
      offsets.set(key, o);
    }
    return o;
  }

  function clock(bars, zone) {
    const n = bars.length, hour = new Array(n), day = new Array(n), week = new Array(n), month = new Array(n), weekday = new Array(n);
    bars.forEach((b, i) => {
      const local = b.time + offsetSeconds(b.time, zone);
      const d = Math.floor(local / 86400);
      day[i] = d;
      week[i] = Math.floor((d + 4) / 7);
      weekday[i] = (d + 4) % 7; // 0 = Sunday
      const dt = new Date(d * 86400000);
      month[i] = dt.getUTCFullYear() * 12 + dt.getUTCMonth();
      hour[i] = (local - d * 86400) / 3600;
    });
    return { hour, day, week, month, weekday };
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

  function cutoffIndexes(ck, hour) {
    const out = [];
    for (let i = 1; i < ck.hour.length; i++) {
      if (ck.hour[i] >= hour && (ck.day[i] !== ck.day[i - 1] || ck.hour[i - 1] < hour)) out.push(i);
    }
    return out;
  }

  /* ---------- gaps ---------- */

  function rawGaps(c, minSize, displacement) {
    const n = c.length, gaps = [];
    if (n < 3) return gaps;
    const tail = c.slice(-100);
    const minimum = tail.reduce((a, b) => a + b.high - b.low, 0) / tail.length * Math.max(minSize, 0);
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
      if (c[i].low > c[i - 2].high && c[i].low - c[i - 2].high > minimum && strong(i - 1, true)) {
        gaps.push({ bull: true, top: c[i].low, bottom: c[i - 2].high, start: i - 1, end: i - 1 });
      } else if (c[i].high < c[i - 2].low && c[i - 2].low - c[i].high > minimum && strong(i - 1, false)) {
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

  // A touched gap stays while price has not traded through it, for `keep` minutes.
  function stillShown(g, c, keep) {
    if (!g.touched || g.end >= c.length) return true;
    for (let j = g.end; j < c.length; j++) if (g.bull ? c[j].low < g.bottom : c[j].high > g.top) return false;
    return c[c.length - 1].time - c[g.end].time <= keep * 60;
  }

  function higherTimeframe(sec) {
    return { 5: 60, 10: 60, 15: 60, 30: 300, 60: 300, 300: 900, 900: 3600, 1800: 14400, 3600: 14400, 14400: 86400, 86400: 604800 }[sec] || null;
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

  function fairValueGaps(c, sec, cfg) {
    const gaps = [];
    const raw = rawGaps(c, cfg.fvgMinSize, cfg.fvgStrong ? cfg.fvgDisplacement : null);
    for (let k = raw.length - 1; k >= 0 && gaps.length < cfg.fvgCount; k--) {
      const g = followed(raw[k], raw[k].start, raw[k].start + 1, c);
      if (g.touched && cfg.fvgHideFilled) continue;
      if (stillShown(g, c, cfg.gapKeep)) gaps.push(g);
    }
    gaps.reverse();
    const higher = higherTimeframe(sec);
    if (cfg.fvgConfluence && higher && gaps.length) {
      const { bars, first } = aggregate(c, higher);
      const earliest = gaps[0].start;
      const big = rawGaps(bars, cfg.fvgMinSize, null).map((r) => {
        const formed = r.start + 3 < first.length ? first[r.start + 3] - 1 : c.length - 1;
        return followed(r, first[r.start], formed, c);
      }).filter((h) => h.end >= earliest);
      gaps.forEach((g) => {
        g.confluence = big.some((h) => h.bull === g.bull && h.bottom < g.top && g.bottom < h.top && h.start <= g.end && g.start <= h.end);
      });
    }
    return gaps;
  }

  function volumeImbalances(c, cfg) {
    const n = c.length, out = [];
    if (n < 3) return out;
    const tail = c.slice(-100);
    const minimum = tail.reduce((a, b) => a + b.high - b.low, 0) / tail.length * 0.03;
    for (let i = n - 1; i >= 1 && out.length < cfg.viCount; i--) {
      const a = c[i - 1], b = c[i];
      let raw = null;
      if (a.close > a.open && b.close > b.open && b.open - a.close > minimum && b.low <= a.high) {
        raw = { bull: true, top: b.open, bottom: a.close, start: i - 1, end: i - 1 };
      } else if (a.close < a.open && b.close < b.open && a.close - b.open > minimum && b.high >= a.low) {
        raw = { bull: false, top: a.close, bottom: b.open, start: i - 1, end: i - 1 };
      }
      if (!raw) continue;
      const g = followed(raw, i - 1, i, c);
      if (g.touched && cfg.viHideTouched) continue;
      if (stillShown(g, c, cfg.gapKeep)) out.push(g);
    }
    return out.reverse();
  }

  function structureBreaks(c, cfg) {
    const length = Math.max(1, cfg.swing), n = c.length, out = [];
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
        const shift = trend === -1;
        if (shift ? cfg.mss : cfg.bos) out.push({ bull: true, shift, price: hi.price, start: hi.index, end: i });
        trend = 1; hi = null;
      }
      if (lo && c[i].close < lo.price) {
        const shift = trend === 1;
        if (shift ? cfg.mss : cfg.bos) out.push({ bull: false, shift, price: lo.price, start: lo.index, end: i });
        trend = -1; lo = null;
      }
    }
    return out.slice(-Math.max(1, cfg.structureCount));
  }

  const WEEKDAYS = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"];

  /* ---------- everything ---------- */

  function compute(c, sec, cfg, show) {
    const out = { boxes: [], levels: [], stamps: [], macros: [], fvgs: [], vis: [], breaks: [], sweeps: [], days: [], ranges: [], hidden: false };
    if (c.length < 3) return out;
    const n = c.length;
    // Second charts count as the smallest minute setting.
    if (show.fvg && cfg.fvg && Math.max(sec, 60) >= cfg.fvgFrom * 60 - 1 && sec <= cfg.fvgTo * 60 + 1) {
      out.fvgs = fairValueGaps(c, sec, cfg);
      if (cfg.vi) out.vis = volumeImbalances(c, cfg);
    }
    if (show.mss && (cfg.mss || cfg.bos)) out.breaks = structureBreaks(c, cfg);
    const ck = clock(c, cfg.timeZone);
    if (show.daily && cfg.daily && sec < 86400) out.levels.push(...dailyLevels(c, ck, cfg));
    if (!show.killzones) return out;
    if (sec > cfg.tfLimit * 60) { out.hidden = true; return out; }
    const firstDay = ck.day[n - 1] - Math.max(cfg.maxDays, 1) + 1;
    const cutoffs = cfg.cutoff ? cutoffIndexes(ck, cfg.cutoffHour) : [];
    const cutAfter = (i) => cutoffs.find((x) => x > i);

    cfg.sessions.forEach((s) => {
      if (!s.on) return;
      const ranges = [];
      for (const [a, b] of windows(ck, s.start, s.end)) {
        let high = -Infinity, low = Infinity, hiI = a, loI = a;
        for (let i = a; i <= b; i++) {
          if (c[i].high > high) { high = c[i].high; hiI = i; }
          if (c[i].low < low) { low = c[i].low; loI = i; }
        }
        ranges.push(high - low);
        if (ck.day[b] < firstDay) continue;
        if (cfg.showBoxes) out.boxes.push({ start: a, end: b, high, low, label: cfg.boxLabels ? s.name : "", color: s.color });
        const mid = (high + low) / 2;
        if (b >= n - 1) {
          // Still open: the running high/low.
          if (cfg.showPivots && cfg.livePivots) {
            out.levels.push({ kind: "pivot", price: high, start: hiI, end: null, label: s.hi, color: s.color });
            out.levels.push({ kind: "pivot", price: low, start: loI, end: null, label: s.lo, color: s.color });
          }
          if (cfg.midpoints && cfg.livePivots) out.levels.push({ kind: "mid", price: mid, start: a, end: b, label: "", color: s.color });
          continue;
        }
        for (const isHigh of [true, false]) {
          const price = isHigh ? high : low;
          const j = firstBreak(c, price, isHigh, b + 1);
          if (cfg.sweeps && j !== null && (isHigh ? c[j].close < price : c[j].close > price)) {
            out.sweeps.push({ bull: !isHigh, price, index: j, label: isHigh ? s.hi : s.lo });
          }
          if (!cfg.showPivots || (j !== null && !cfg.keepMitigated)) continue;
          let end = cfg.pivotUntilMitigated ? j : null;
          const cut = cutAfter(b);
          if (cut !== undefined && (end === null || cut < end)) end = cut;
          out.levels.push({ kind: "pivot", price, start: isHigh ? hiI : loI, end, label: isHigh ? s.hi : s.lo, color: s.color, mitigated: j !== null });
        }
        if (cfg.midpoints) out.levels.push({ kind: "mid", price: mid, start: a, end: b, label: "", color: s.color });
      }
      if (ranges.length) {
        const recent = ranges.slice(-Math.max(cfg.rangeAvg, 1));
        out.ranges.push({ name: s.name, color: s.color, latest: ranges[ranges.length - 1], average: recent.reduce((x, y) => x + y, 0) / recent.length });
      }
    });

    if (cfg.macros && sec <= cfg.macroTfLimit * 60) {
      cfg.macroList.forEach((m) => {
        if (!m.on) return;
        for (const [a, b] of windows(ck, m.start, m.end)) {
          if (ck.day[b] < firstDay) continue;
          let high = -Infinity, low = Infinity;
          for (let i = a; i <= b; i++) { high = Math.max(high, c[i].high); low = Math.min(low, c[i].low); }
          const h = Math.floor(m.start), mm = Math.round((m.start - h) * 60);
          out.macros.push({ start: a, end: b, high, low, label: cfg.macroTimeLabels ? `${String(h).padStart(2, "0")}:${String(mm).padStart(2, "0")}` : m.name });
        }
      });
    }

    cfg.opens.forEach((o) => {
      if (!o.on) return;
      const starts = markIndexes(ck, o.hour, firstDay);
      starts.forEach((st, k) => {
        let end = k + 1 < starts.length ? starts[k + 1] - 1 : null;
        const cut = cutAfter(st);
        if (cut !== undefined && (end === null || cut < end)) end = cut;
        out.levels.push({ kind: "open", price: c[st].open, start: st, end, label: o.label, color: o.color });
      });
    });
    cfg.stamps.forEach((m) => { if (m.on) out.stamps.push(...markIndexes(ck, m.hour, firstDay)); });

    // Previous day / week / month highs and lows across the current period.
    const previous = (id) => {
      const cur = id[n - 1];
      let start = n - 1;
      while (start > 0 && id[start - 1] === cur) start--;
      if (start === 0) return null;
      const prev = id[start - 1];
      let high = -Infinity, low = Infinity, hiI = start - 1, loI = start - 1;
      for (let i = start - 1; i >= 0 && id[i] === prev; i--) {
        if (c[i].high > high) { high = c[i].high; hiI = i; }
        if (c[i].low < low) { low = c[i].low; loI = i; }
      }
      return { start, high, low, hiI, loI };
    };
    const pd = previous(ck.day);
    if (cfg.sweeps && pd) {
      [[true, pd.high, "PDH"], [false, pd.low, "PDL"]].forEach(([isHigh, price, label]) => {
        const j = firstBreak(c, price, isHigh, pd.start);
        if (j !== null && (isHigh ? c[j].close < price : c[j].close > price)) out.sweeps.push({ bull: !isHigh, price, index: j, label });
      });
    }
    [[cfg.prevDay, ck.day, "PDH", "PDL"], [cfg.prevWeek, ck.week, "PWH", "PWL"], [cfg.prevMonth, ck.month, "PMH", "PML"]].forEach(([on, id, h, l]) => {
      if (!on) return;
      const r = previous(id);
      if (!r) return;
      // A candle crossing the level ends it there (it stays on the chart to be seen).
      [[true, r.high, h], [false, r.low, l]].forEach(([isHigh, price, name]) => {
        const j = cfg.periodUntilBroken ? firstBreak(c, price, isHigh, r.start) : null;
        out.levels.push({ kind: "period", price, start: r.start, end: j, label: name, color: cfg.periodColor, mitigated: j !== null });
      });
    });
    if (cfg.dayOfWeek) markIndexes(ck, 12, firstDay).forEach((i) => out.days.push({ index: i, label: WEEKDAYS[ck.weekday[i]] }));
    out.sweeps = out.sweeps.sort((a, b) => a.index - b.index).slice(-Math.max(cfg.sweepCount, 1));
    if (!cfg.sweeps) out.sweeps = [];
    if (!cfg.rangeTable) out.ranges = [];
    return out;
  }

  // High and low of each of the last finished days, until a candle reaches them.
  function dailyLevels(c, ck, cfg) {
    const n = c.length, today = ck.day[n - 1], ranges = [];
    let end = n - 1;
    while (end >= 0 && ck.day[end] === today) end--;
    while (end >= 0 && ranges.length < Math.max(cfg.dailyDays, 1)) {
      let start = end;
      while (start > 0 && ck.day[start - 1] === ck.day[end]) start--;
      ranges.push([start, end]);
      end = start - 1;
    }
    const levels = [];
    ranges.reverse().forEach(([a, b]) => {
      let hiI = a, loI = a;
      for (let i = a; i <= b; i++) { if (c[i].high > c[hiI].high) hiI = i; if (c[i].low < c[loI].low) loI = i; }
      const wd = WEEKDAYS[ck.weekday[a]];
      [[true, hiI, c[hiI].high], [false, loI, c[loI].low]].forEach(([isHigh, st, price]) => {
        const touch = firstTouch(c, price, isHigh, b + 1);
        if (touch !== null && !cfg.dailyKeepTouched) return;
        levels.push({ kind: "daily", price, start: st, end: touch, label: (isHigh ? "Đỉnh " : "Đáy ") + wd,
          color: isHigh ? cfg.dayHighColor : cfg.dayLowColor, mitigated: touch !== null });
      });
    });
    return levels;
  }

  /* ---------- drawing ---------- */

  const DASH = { solid: [], dashed: [6, 4], dotted: [2, 3] };

  /** Paints `o` on a 2D context in CSS pixels; X(index) and Y(price) give coordinates. */
  function draw(g, o, cfg, X, Y, w, h) {
    if (!o) return;
    const s = cfg.lineScale || 1;
    const x0 = X(0), x1 = X(1);
    const half = x0 != null && x1 != null ? Math.max(0.5, (x1 - x0) / 2) : 2;
    const xEnd = (end) => (end == null ? w : X(end) + half);
    g.save();
    g.font = "10px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
    g.textBaseline = "bottom";
    const line = (a, b, y, color, width = 1, dash = []) => {
      if (y == null || a == null || b == null || b < 0 || a > w) return;
      g.strokeStyle = color; g.lineWidth = width * s; g.setLineDash(dash);
      g.beginPath(); g.moveTo(a, Math.round(y) + 0.5); g.lineTo(b, Math.round(y) + 0.5); g.stroke();
    };
    const label = (text, x, y, color, align = "right") => {
      if (!text || y == null || x == null) return;
      g.fillStyle = color; g.textAlign = align;
      g.fillText(text, Math.min(Math.max(x, 2), w - 2), y - 2);
    };
    const alpha = (hex, a) => hex + Math.round(Math.max(0, Math.min(1, a)) * 255).toString(16).padStart(2, "0");

    if (o.hidden) { g.fillStyle = "#8b95a7"; g.textAlign = "left"; g.textBaseline = "top"; g.fillText(`Killzones chỉ hiện ở khung ≤ ${cfg.tfLimit >= 60 ? cfg.tfLimit / 60 + "h" : cfg.tfLimit + "m"}`, 8, 8); g.textBaseline = "bottom"; }

    o.stamps.forEach((i) => {
      const x = X(i);
      if (x == null || x < 0 || x > w) return;
      g.strokeStyle = alpha(cfg.stampColor, 0.45); g.lineWidth = 1; g.setLineDash(DASH[cfg.stampStyle] || []);
      g.beginPath(); g.moveTo(Math.round(x - half) + 0.5, 0); g.lineTo(Math.round(x - half) + 0.5, h); g.stroke();
    });

    o.boxes.forEach((b) => {
      const a = X(b.start), e = X(b.end), y1 = Y(b.high), y2 = Y(b.low);
      if (a == null || e == null || y1 == null || y2 == null) return;
      const l = a - half, r = e + half;
      if (r < 0 || l > w) return;
      g.fillStyle = alpha(b.color, (cfg.boxOpacity || 12) / 100);
      g.fillRect(l, y1, r - l, y2 - y1);
      if (cfg.boxBorder) {
        g.setLineDash([]); g.strokeStyle = alpha(b.color, 0.4); g.lineWidth = 1;
        g.strokeRect(Math.round(l) + 0.5, Math.round(y1) + 0.5, Math.round(r - l), Math.round(y2 - y1));
      }
      label(b.label, l + 2, y1, b.color, "left");
    });

    o.macros.forEach((b) => {
      const a = X(b.start), e = X(b.end), y1 = Y(b.high), y2 = Y(b.low);
      if (a == null || e == null || y1 == null || y2 == null) return;
      g.setLineDash([2, 2]); g.strokeStyle = alpha(cfg.macroColor, 0.7); g.lineWidth = 1;
      g.strokeRect(Math.round(a - half) + 0.5, Math.round(y1) + 0.5, Math.round(e - a + 2 * half), Math.round(y2 - y1));
      g.textAlign = "left"; g.fillStyle = alpha(cfg.macroColor, 0.9);
      g.fillText(b.label, a - half + 1, y1 - 1);
    });

    o.levels.forEach((l) => {
      const a = X(l.start), b = xEnd(l.end), y = Y(l.price);
      if (a == null) return;
      if (l.kind === "daily") {
        line(a, b, y, alpha(l.color, l.mitigated ? 0.6 : 0.85), 1, l.mitigated ? DASH.dotted : DASH[cfg.dailyStyle]);
        label(l.label, b - 2, y, alpha(l.color, 0.8));
        return;
      }
      if (l.kind === "open") { line(a, b, y, alpha(l.color, 0.75), 1, DASH[cfg.openStyle]); label(l.label, b - 2, y, l.color); return; }
      if (l.kind === "period") { line(a, b, y, alpha(l.color, l.mitigated ? 0.7 : 1), 1, DASH.dashed); label(l.label, b - 2, y, alpha(l.color, l.mitigated ? 0.75 : 1)); return; }
      if (l.kind === "mid") { line(a, b, y, alpha(l.color, 0.6), 1, DASH.dotted); return; }
      line(a, b, y, alpha(l.color, l.mitigated ? 0.55 : 0.95), cfg.pivotWidth, DASH[l.mitigated ? cfg.mitigatedStyle : cfg.pivotStyle]);
      if (cfg.pivotLabels) label(l.label, b - 2, y, l.color);
    });

    o.fvgs.forEach((f) => {
      const a = X(f.start), e = X(f.end), yt = Y(f.top), yb = Y(f.bottom);
      if (a == null || e == null || yt == null || yb == null) return;
      const l = a - half, r = e + half;
      if (r < 0 || l > w) return;
      const color = alpha(f.bull ? cfg.fvgBull : cfg.fvgBear, f.touched ? 0.6 : 1);
      if (f.confluence) { g.fillStyle = alpha(cfg.fvgZone, 0.15); g.fillRect(l, yt, r - l, yb - yt); }
      line(l, r, yt, color, 1.2); line(l, r, yb, color, 1.2);
      if (cfg.fvgMid) line(l, r, (yt + yb) / 2, f.confluence ? cfg.fvgZoneMid : color, 0.8, [3, 3]);
    });
    o.vis.forEach((f) => {
      const a = X(f.start), e = X(f.end);
      if (a == null || e == null) return;
      const color = alpha(cfg.viColor, f.touched ? 0.55 : 1);
      line(a - half, e + half, Y(f.top), color, 0.8, [3, 2]); line(a - half, e + half, Y(f.bottom), color, 0.8, [3, 2]);
    });

    o.breaks.forEach((b) => {
      const a = X(b.start), e = X(b.end), y = Y(b.price);
      if (a == null || e == null || y == null) return;
      const color = b.bull ? cfg.mssBull : cfg.mssBear;
      line(a, e, y, color, 1, b.shift ? [4, 3] : []);
      g.fillStyle = color; g.textAlign = "center"; g.textBaseline = b.bull ? "bottom" : "top";
      g.fillText(b.shift ? "MSS" : "BOS", (a + e) / 2, b.bull ? y - 2 : y + 2);
      g.textBaseline = "bottom";
    });

    o.sweeps.forEach((sw) => {
      const x = X(sw.index), y = Y(sw.price);
      if (x == null || y == null || x < 0 || x > w) return;
      g.fillStyle = cfg.sweepColor; g.textAlign = "center"; g.textBaseline = sw.bull ? "top" : "bottom";
      g.fillText("✕ " + sw.label, x, sw.bull ? y + 3 : y - 3);
      g.textBaseline = "bottom";
    });

    o.days.forEach((d) => {
      const x = X(d.index);
      if (x == null || x < 0 || x > w) return;
      g.fillStyle = "#8b95a7"; g.textAlign = "center"; g.fillText(d.label, x, h - 4);
    });

    if (o.ranges.length) {
      g.textAlign = "left"; g.textBaseline = "top";
      const rows = o.ranges.length + 1, bw = 170, bh = rows * 15 + 8;
      g.fillStyle = "rgba(12,17,27,.85)"; g.fillRect(w - bw - 8, 8, bw, bh);
      g.fillStyle = "#8b95a7"; g.fillText("Phiên      gần nhất   TB", w - bw - 2, 12);
      o.ranges.forEach((r, i) => {
        g.fillStyle = r.color; g.fillText(r.name, w - bw - 2, 27 + i * 15);
        g.fillStyle = "#e8ecf3"; g.fillText(r.latest.toFixed(2), w - bw + 66, 27 + i * 15); g.fillText(r.average.toFixed(2), w - bw + 120, 27 + i * 15);
      });
    }
    g.restore();
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
    let shark = null, sum = 0;
    const sharks = [];
    for (let i = 0; i < n; i++) {
      if (i >= length) {
        const avg = sum / length, ratio = avg > 0 ? weight[i] / avg : 0;
        if (ratio >= 2.5 && Math.abs(pressure[i]) >= 0.33) {
          sharks.push({ index: i, buying: pressure[i] > 0, ratio });
          if (i >= n - 30) shark = { buying: pressure[i] > 0, ratio };
        }
        sum -= weight[i - length];
      }
      sum += weight[i];
    }
    return { flow, situation, shark, sharks };
  }

  /* ---------- SMT divergence against a related market ---------- */

  /**
   * Two swing highs (lows) in a row where one market makes a higher high (lower low)
   * and the other does not — the app's rule. Bars of `b` are matched to `a` by time.
   */
  function smt(a, b, opts = {}) {
    const length = Math.max(opts.swing || 3, 1), lookback = opts.lookback || 60, count = opts.count || 10, inverse = !!opts.inverse;
    const n = a.length;
    if (n <= length * 2 + 2 || !b.length) return [];
    const other = new Map(b.map((x) => [x.time, x]));
    const extreme = (p, high) => {
      const values = [];
      for (let i = Math.max(0, p - 1); i <= Math.min(n - 1, p + 1); i++) { const o = other.get(a[i].time); if (o) values.push(high ? o.high : o.low); }
      return values.length ? (high ? Math.max(...values) : Math.min(...values)) : null;
    };
    const highs = [], lows = [];
    for (let p = length; p < n - length; p++) {
      let hi = true, lo = true;
      for (let j = p - length; j <= p + length; j++) {
        if (j === p) continue;
        if (a[j].high >= a[p].high) hi = false;
        if (a[j].low <= a[p].low) lo = false;
      }
      if (hi) highs.push(p);
      if (lo) lows.push(p);
    }
    const out = [];
    for (let k = 1; k < highs.length; k++) {
      const i1 = highs[k - 1], i2 = highs[k];
      if (i2 - i1 > lookback) continue;
      const b1 = extreme(i1, !inverse), b2 = extreme(i2, !inverse);
      if (b1 == null || b2 == null) continue;
      if ((a[i2].high > a[i1].high) !== (inverse ? b2 < b1 : b2 > b1)) out.push({ bull: false, start: i1, end: i2, p1: a[i1].high, p2: a[i2].high, t1: a[i1].time, t2: a[i2].time });
    }
    for (let k = 1; k < lows.length; k++) {
      const i1 = lows[k - 1], i2 = lows[k];
      if (i2 - i1 > lookback) continue;
      const b1 = extreme(i1, inverse), b2 = extreme(i2, inverse);
      if (b1 == null || b2 == null) continue;
      if ((a[i2].low < a[i1].low) !== (inverse ? b2 > b1 : b2 < b1)) out.push({ bull: true, start: i1, end: i2, p1: a[i1].low, p2: a[i2].low, t1: a[i1].time, t2: a[i2].time });
    }
    return out.sort((m, k) => m.end - k.end).slice(-count);
  }

  /** SMT lines with their label; X(index) / Y(price) as in draw(). */
  function drawSMT(g, list, X, Y, w, colors = {}) {
    if (!list || !list.length) return;
    g.save();
    g.font = "600 10px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
    list.forEach((d) => {
      const x1 = X(d.start), x2 = X(d.end), y1 = Y(d.p1), y2 = Y(d.p2);
      if (x1 == null || x2 == null || y1 == null || y2 == null || x2 < 0 || x1 > w) return;
      const c = d.bull ? colors.bull || "#089981" : colors.bear || "#f23645";
      g.strokeStyle = c; g.lineWidth = 1.2; g.setLineDash([]);
      g.beginPath(); g.moveTo(x1, y1); g.lineTo(x2, y2); g.stroke();
      g.fillStyle = c; g.textAlign = "center"; g.textBaseline = d.bull ? "top" : "bottom";
      g.fillText("SMT", (x1 + x2) / 2, (d.bull ? Math.max(y1, y2) + 3 : Math.min(y1, y2) - 3));
    });
    g.restore();
  }

  /** Shark bubbles like the app: a big buyer under its candle, a big seller above it. */
  function drawSharks(g, list, bars, X, Y, w, up, down) {
    if (!list || !list.length) return;
    g.save();
    g.textAlign = "center"; g.textBaseline = "middle";
    list.forEach((s) => {
      const b = bars[s.index], x = X(s.index);
      if (!b || x == null || x < -20 || x > w + 20) return;
      const r = Math.min(5 + s.ratio * 1.6, 16);
      const yy = s.buying ? Y(b.low) : Y(b.high);
      if (yy == null) return;
      const y = s.buying ? yy + r + 3 : yy - r - 3;
      const color = s.buying ? up : down;
      g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2);
      g.fillStyle = color + "59"; g.fill();
      g.lineWidth = 1; g.strokeStyle = color; g.stroke();
      if (r >= 9) { g.font = `${Math.round(r)}px system-ui, sans-serif`; g.fillText("🦈", x, y + 1); }
    });
    g.restore();
  }

  window.ICT = { drawSharks, defaults, merge, compute, draw, sharkFlow, smt, drawSMT };
})();
