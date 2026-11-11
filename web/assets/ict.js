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
      // Session highs/lows in the session's colour or their own; where the level names sit on their lines.
      pivotColorMode: "session", pivotHighColor: "#089981", pivotLowColor: "#f23645", levelLabelAlign: "right",
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
      // Day / week / month: this period's open, the last period's high / low and middle, a line where each starts.
      dwm: [
        { key: "D", open: true, hl: true, mid: true, divider: false, color: "#787b86" },
        { key: "W", open: false, hl: true, mid: true, divider: false, color: "#f23645" },
        { key: "M", open: false, hl: false, mid: false, divider: false, color: "#9c27b0" },
      ],
      dwmStyle: "solid", dwmWidth: 1, dwmAlert: false,
      // Weekday names under (or over) each day, at its midnight or midday; weekends can be left out.
      dayOfWeek: false, dowPos: "bottom", dowAt: "midnight", dowHideWeekend: false,
      rangeTable: false, rangeAvg: 5,
      // The first FVG of each Monday after 09:30 Vietnam time, carried to the end of that week.
      weekFvg: true, weekFvgWeeks: 4, weekFvgColor: "#2962ff",
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
      // viKeep: a VI a candle touches or trades through stays, ending at that candle.
      vi: true, viCount: 20, viHideTouched: false, viKeep: true, viVersion: 2, viColor: "#fa9900",
      mss: true, bos: false, swing: 5, structureCount: 20, mssBull: "#089981", mssBear: "#f23645",
      sweeps: true, sweepCount: 20, sweepColor: "#fa9900",
      // DM: strong candles with (almost) no wicks — body ≥ dmBody × ATR(14), each wick ≤ dmWick % of the candle.
      dmBody: 1, dmWick: 0, dmCount: 10, dmUntilBroken: false, dmLineColor: "#787b86", dmTextColor: "#f23645", dmStyle: "solid", dmWidth: 1, dmVersion: 2,
      dailyLabelAlign: "center",
      lineScale: 1,
      // SMT against a related market (silver for gold): empty symbol = automatic.
      smtSymbol: "", smtInverse: false, smtSwing: 5, smtLookback: 60, smtCount: 5, smtBull: "#089981", smtBear: "#f23645",
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
    // SMT v3: the old defaults (3-bar swings, 10 kept) gave a line on nearly every swing.
    if (saved.smtVersion !== 2 && saved.smtVersion !== 3) {
      if (d.smtSwing === 3) d.smtSwing = 5;
      if (d.smtCount === 10) d.smtCount = 5;
      d.smtVersion = 3;
    }
    if (saved.smtVersion === 2) { if (d.smtCount === 3) d.smtCount = 5; d.smtVersion = 3; }
    // D/W/M replaces the three PDH / PWH / PMH switches and their one colour.
    if (!Array.isArray(saved.dwm)) {
      if (saved.prevWeek) d.dwm[1].hl = true;
      if (saved.prevMonth) d.dwm[2].hl = true;
    }
    if (saved.keepVersion !== 2) {
      d.keepMitigated = true; d.pivotUntilMitigated = true; d.dailyKeepTouched = true; d.periodUntilBroken = true;
      d.keepVersion = 2;
    }
    if (saved.viVersion !== 2) {
      // Touched VIs now stay (ending at the touching candle) instead of going.
      d.viKeep = true; d.viHideTouched = false; d.viVersion = 2;
    }
    if (saved.dmVersion !== 2) {
      // DM became lines from candles bare on one side: the first version's size settings do not carry over.
      const fresh = defaults();
      ["dmBody", "dmWick", "dmCount", "dmVersion"].forEach((k) => { d[k] = fresh[k]; });
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
      if (cfg.viKeep || stillShown(g, c, cfg.gapKeep)) out.push(g);
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

  /** The period before the newest bar's one (`id` per bar: day, week or month number): its high, low and bars. */
  function previousPeriod(c, id) {
    const n = c.length, cur = id[n - 1];
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
  }

  /** Each week's first fair value gap made on Monday after 09:30 Vietnam time (UTC+7): the three candles
   *  of the gap from 09:30 on, all on that Monday. From its middle candle to the week's last bar (the right
   *  edge for the running week). `touched`: a later candle of the week came back into it. Newest `weekFvgWeeks`. */
  function mondayFvgs(c, cfg) {
    const n = c.length, VN = 7 * 3600;
    const vnDay = (t) => Math.floor((t + VN) / 86400);
    const week = (t) => Math.floor((vnDay(t) + 3) / 7); // changes on Mondays (1970-01-01 was a Thursday)
    const mondayAfter = (t) => { const d = vnDay(t); return (d + 4) % 7 === 1 && (t + VN) - d * 86400 >= 9.5 * 3600; };
    const out = [], done = new Set();
    for (let i = 2; i < n; i++) {
      const wk = week(c[i].time);
      if (done.has(wk)) continue;
      if (!mondayAfter(c[i - 2].time) || vnDay(c[i].time) !== vnDay(c[i - 2].time)) continue;
      const bull = c[i].low > c[i - 2].high, bear = c[i].high < c[i - 2].low;
      if (!bull && !bear) continue;
      done.add(wk);
      let end = i;
      while (end + 1 < n && week(c[end + 1].time) === wk) end++;
      const top = bull ? c[i].low : c[i - 2].low, bottom = bull ? c[i - 2].high : c[i].high;
      let touched = false;
      for (let j = i + 1; j <= end && !touched; j++) if (c[j].low <= top && c[j].high >= bottom) touched = true;
      out.push({ bull, top, bottom, start: i - 1, end: end === n - 1 ? null : end, touched });
    }
    return out.slice(-Math.max(1, cfg.weekFvgWeeks || 1));
  }

  const DWM = {
    D: { id: "day", size: 86400, open: "DO", hi: "PDH", lo: "PDL", mid: "PDM", name: "ngày" },
    W: { id: "week", size: 7 * 86400, open: "WO", hi: "PWH", lo: "PWL", mid: "PWM", name: "tuần" },
    M: { id: "month", size: 28 * 86400, open: "MO", hi: "PMH", lo: "PML", mid: "PMM", name: "tháng" },
  };

  /** Day / week / month levels (on charts below that period): the open of the current one, the last one's
   *  high / low (until a candle crosses it, with periodUntilBroken) and middle, and a divider at each start.
   *  Weekday labels too. `out.periodBreaks` lists the highs / lows the newest bar crossed (for the alert). */
  function periodLevels(c, ck, sec, cfg, out) {
    const n = c.length;
    out.dividers = [];
    out.periodBreaks = [];
    (cfg.dwm || []).forEach((p) => {
      const def = DWM[p.key];
      if (!def || sec >= def.size || !(p.open || p.hl || p.mid || p.divider)) return;
      const id = ck[def.id];
      const color = p.color || "#787b86";
      if (p.divider) for (let i = 1; i < n; i++) if (id[i] !== id[i - 1]) out.dividers.push({ index: i, color });
      if (p.open) {
        let st = n - 1;
        while (st > 0 && id[st - 1] === id[n - 1]) st--;
        if (st > 0) out.levels.push({ kind: "dwm", price: c[st].open, start: st, end: null, label: def.open, color });
      }
      const r = previousPeriod(c, id);
      if (!r) return;
      if (p.hl) {
        [[true, r.high, def.hi], [false, r.low, def.lo]].forEach(([isHigh, price, name]) => {
          const j = firstBreak(c, price, isHigh, r.start);
          if (j === n - 1) out.periodBreaks.push({ label: name, price, high: isHigh, time: c[j].time });
          out.levels.push({ kind: "dwm", price, start: r.start, end: cfg.periodUntilBroken ? j : null, label: name, color, mitigated: j !== null });
        });
      }
      if (p.mid) out.levels.push({ kind: "dwm", price: (r.high + r.low) / 2, start: r.start, end: null, label: def.mid, color, mid: true });
    });
    if (cfg.dayOfWeek && sec < 86400) {
      const hour = cfg.dowAt === "midday" ? 12 : 0;
      for (let i = 0; i < n; i++) {
        if (i > 0 && ck.day[i] === ck.day[i - 1] && !(ck.hour[i - 1] < hour && ck.hour[i] >= hour)) continue;
        if (ck.hour[i] < hour && (i === n - 1 || ck.day[i + 1] === ck.day[i])) continue;
        const wd = ck.weekday[i];
        if (cfg.dowHideWeekend && (wd === 0 || wd === 6)) continue;
        out.days.push({ index: i, label: WEEKDAYS[wd] });
      }
    }
  }

  /* ---------- everything ---------- */

  function compute(c, sec, cfg, show) {
    const out = { boxes: [], levels: [], stamps: [], macros: [], fvgs: [], vis: [], breaks: [], sweeps: [], days: [], ranges: [], weekFvgs: [], hidden: false };
    if (c.length < 3) return out;
    const n = c.length;
    // Second charts count as the smallest minute setting.
    if (show.fvg && cfg.fvg && Math.max(sec, 60) >= cfg.fvgFrom * 60 - 1 && sec <= cfg.fvgTo * 60 + 1) {
      out.fvgs = fairValueGaps(c, sec, cfg);
      if (cfg.vi) out.vis = volumeImbalances(c, cfg);
    }
    if (show.mss && (cfg.mss || cfg.bos)) out.breaks = structureBreaks(c, cfg);
    if (show.dm) out.dms = strongCandles(c, cfg);
    const ck = clock(c, cfg.timeZone);
    if (show.daily && cfg.daily && sec < 86400) out.levels.push(...dailyLevels(c, ck, cfg));
    if (!show.killzones) return out;
    periodLevels(c, ck, sec, cfg, out);
    if (cfg.weekFvg && sec < 86400) out.weekFvgs = mondayFvgs(c, cfg);
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
            out.levels.push({ kind: "pivot", price: high, start: hiI, end: null, label: s.hi, color: s.color, high: true });
            out.levels.push({ kind: "pivot", price: low, start: loI, end: null, label: s.lo, color: s.color, high: false });
          }
          if (cfg.midpoints && cfg.livePivots) out.levels.push({ kind: "mid", price: mid, start: a, end: b, label: "", color: s.color });
          continue;
        }
        for (const isHigh of [true, false]) {
          const price = isHigh ? high : low;
          const j = firstBreak(c, price, isHigh, b + 1);
          if (cfg.sweeps && j !== null && (isHigh ? c[j].close < price : c[j].close > price)) {
            out.sweeps.push({ bull: !isHigh, price, index: j, from: isHigh ? hiI : loI, label: isHigh ? s.hi : s.lo });
          }
          if (!cfg.showPivots || (j !== null && !cfg.keepMitigated)) continue;
          let end = cfg.pivotUntilMitigated ? j : null;
          const cut = cutAfter(b);
          if (cut !== undefined && (end === null || cut < end)) end = cut;
          out.levels.push({ kind: "pivot", price, start: isHigh ? hiI : loI, end, label: isHigh ? s.hi : s.lo, color: s.color, mitigated: j !== null, high: isHigh });
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

    const pd = previousPeriod(c, ck.day);
    if (cfg.sweeps && pd) {
      [[true, pd.high, "PDH", pd.hiI], [false, pd.low, "PDL", pd.loI]].forEach(([isHigh, price, label, from]) => {
        const j = firstBreak(c, price, isHigh, pd.start);
        if (j !== null && (isHigh ? c[j].close < price : c[j].close > price)) out.sweeps.push({ bull: !isHigh, price, index: j, from, label });
      });
    }
    out.sweeps = out.sweeps.sort((a, b) => a.index - b.index).slice(-Math.max(cfg.sweepCount, 1));
    if (!cfg.sweeps) out.sweeps = [];
    if (!cfg.rangeTable) out.ranges = [];
    return out;
  }

  // High and low of each of the last finished days, until a candle reaches them.
  /** DM: strong candles with no wick on one side (body ≥ dmBody × ATR(14); 0 takes any size). Each gives a level
   *  at its bare end — the high with no upper wick, the low with no lower wick — carried right to the newest
   *  candle (or to the first candle crossing it), to compare price with. */
  function strongCandles(c, cfg) {
    const out = [], n = c.length, len = 14;
    let atr = 0;
    for (let i = 1; i < n; i++) {
      const tr = Math.max(c[i].high - c[i].low, Math.abs(c[i].high - c[i - 1].close), Math.abs(c[i].low - c[i - 1].close));
      atr = i <= len ? atr + (tr - atr) / i : atr + (tr - atr) / len;
      if (i < len) continue;
      const b = c[i], range = b.high - b.low, body = Math.abs(b.close - b.open);
      if (range <= 0 || body <= 0 || body < (cfg.dmBody || 0) * atr) continue;
      // "No wick": within dmWick % of the candle (0 = none at all, with a hair for rounding).
      const most = Math.max((cfg.dmWick || 0) / 100 * range, range * 1e-6);
      const top = b.high - Math.max(b.open, b.close), bottom = Math.min(b.open, b.close) - b.low;
      for (const [bare, isHigh, price] of [[top <= most, true, b.high], [bottom <= most, false, b.low]]) {
        if (!bare) continue;
        const end = cfg.dmUntilBroken ? firstBreak(c, price, isHigh, i + 1) : null;
        out.push({ index: i, price, high: isHigh, end });
      }
    }
    return out.slice(-Math.max(cfg.dmCount || 10, 1));
  }

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
    // A level's name at its line's left end, middle or right end (the visible part of it).
    const levelLabel = (text, a, b, y, color, align = cfg.levelLabelAlign || "right") => {
      // At the left end the name goes under the line: above it sits the session box's own name.
      if (align === "left") label(text, Math.max(a, 0) + 2, y == null ? y : y + 12, color, "left");
      else if (align === "center") label(text, (Math.max(a, 0) + Math.min(b, w)) / 2, y, color, "center");
      else label(text, b - 2, y, color);
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
        levelLabel(l.label, a, b, y, alpha(l.color, 0.8), cfg.dailyLabelAlign || "center");
        return;
      }
      if (l.kind === "open") { line(a, b, y, alpha(l.color, 0.75), 1, DASH[cfg.openStyle]); levelLabel(l.label, a, b, y, l.color); return; }
      if (l.kind === "dwm") {
        const c7 = (l.color || "#787b86").slice(0, 7);
        line(a, b, y, alpha(c7, l.mitigated ? 0.6 : l.mid ? 0.75 : 1), cfg.dwmWidth || 1, l.mid ? DASH.dotted : DASH[cfg.dwmStyle] || []);
        levelLabel(l.label, a, b, y, alpha(c7, l.mitigated ? 0.7 : 1));
        return;
      }
      if (l.kind === "mid") { line(a, b, y, alpha(l.color, 0.6), 1, DASH.dotted); return; }
      const pc = (cfg.pivotColorMode === "custom" ? (l.high ? cfg.pivotHighColor : cfg.pivotLowColor) : l.color || "#787b86").slice(0, 7);
      line(a, b, y, alpha(pc, l.mitigated ? 0.55 : 0.95), cfg.pivotWidth, DASH[l.mitigated ? cfg.mitigatedStyle : cfg.pivotStyle]);
      if (cfg.pivotLabels) levelLabel(l.label, a, b, y, pc);
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
    // Monday's first FVG after 09:30 (VN): a band to the end of its week, its middle and its name.
    (o.weekFvgs || []).forEach((f) => {
      const a = X(f.start), e = f.end == null ? w : X(f.end) + half, yt = Y(f.top), yb = Y(f.bottom);
      if (a == null || e == null || yt == null || yb == null) return;
      const l = a - half;
      if (e < 0 || l > w) return;
      const c7 = (cfg.weekFvgColor || "#2962ff").slice(0, 7);
      g.fillStyle = alpha(c7, 0.12); g.fillRect(l, yt, e - l, yb - yt);
      line(l, e, yt, alpha(c7, 0.9), 1); line(l, e, yb, alpha(c7, 0.9), 1);
      line(l, e, (yt + yb) / 2, alpha(c7, 0.7), 0.8, [4, 3]);
      g.fillStyle = c7; g.textAlign = "left";
      g.fillText(`FVG T2 ${f.bull ? "tăng" : "giảm"}`, Math.max(l, 0) + 3, yt - 2);
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

    // A sweep: a faint line from the swept high/low to the candle that took it, an X in the middle.
    o.sweeps.forEach((sw) => {
      const x = X(sw.index), y = Y(sw.price), xf = sw.from != null ? X(sw.from) : null;
      if (x == null || y == null) return;
      const a = xf != null ? Math.min(xf, x) : x - 30, b = x;
      if (b < 0 || a > w) return;
      line(a, b, y, alpha(cfg.sweepColor.slice(0, 7), 0.55), 1, DASH.dotted);
      const mx = (Math.max(a, 0) + Math.min(b, w)) / 2; // the middle of the part on screen
      g.save();
      g.font = "700 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
      g.fillStyle = cfg.sweepColor; g.textAlign = "center"; g.textBaseline = "middle";
      g.fillText("X", mx, Math.round(y) + 0.5);
      g.restore();
    });

    // DM: a line from the candle's bare end to the right, "DM" in the middle of the part on screen.
    (o.dms || []).forEach((d) => {
      const a = X(d.index), y = Y(d.price);
      if (a == null || y == null) return;
      const b = xEnd(d.end);
      if (b < 0 || a > w) return;
      line(a - half, b, y, (cfg.dmLineColor || "#131722").slice(0, 7), cfg.dmWidth || 1, DASH[cfg.dmStyle] || []);
      g.save();
      g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
      g.fillStyle = (cfg.dmTextColor || "#f23645").slice(0, 7); g.textAlign = "center";
      g.textBaseline = d.high ? "bottom" : "top";
      g.fillText("DM", (Math.max(a, 0) + Math.min(b, w)) / 2, d.high ? Math.round(y) - 2 : Math.round(y) + 3);
      g.restore();
    });

    (o.dividers || []).forEach((d) => {
      const x = X(d.index);
      if (x == null || x < 0 || x > w) return;
      g.strokeStyle = alpha(d.color.slice(0, 7), 0.6); g.lineWidth = 1; g.setLineDash(DASH[cfg.dwmStyle] || []);
      g.beginPath(); g.moveTo(Math.round(x - half) + 0.5, 0); g.lineTo(Math.round(x - half) + 0.5, h); g.stroke();
    });
    g.setLineDash([]);
    o.days.forEach((d) => {
      const x = X(d.index);
      if (x == null || x < 0 || x > w) return;
      g.fillStyle = "#8b95a7"; g.textAlign = "center";
      if (cfg.dowPos === "top") { g.textBaseline = "top"; g.fillText(d.label, x, 4); g.textBaseline = "bottom"; } else g.fillText(d.label, x, h - 4);
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
    return { flow, situation, shark, sharks, zones: sharkZones(c, pressure, weight, sharks) };
  }

  /**
   * Supply / demand of the shark flow (the app's SharkFlow.zones): volume at price over the last `lookback`
   * bars, split into buying and selling by where each bar closed (shark bars count `ratio` times). Rows under
   * the price where buying beat selling the most are demand (big players wait to buy there), rows above it
   * where selling won are supply; neighbouring rows at least 80 % as strong join, three rows at most.
   */
  function sharkZones(c, pressure, weight, sharks, lookback = 300, rows = 120, count = 2) {
    const n = c.length, from = Math.max(0, n - lookback);
    if (n - from < 10) return [];
    let lo = Infinity, hi = -Infinity;
    for (let i = from; i < n; i++) { lo = Math.min(lo, c[i].low); hi = Math.max(hi, c[i].high); }
    if (!(hi > lo)) return [];
    const step = (hi - lo) / rows, buy = new Array(rows).fill(0), sell = new Array(rows).fill(0);
    const boost = new Map();
    sharks.forEach((s) => boost.set(s.index, Math.max(boost.get(s.index) || 0, s.ratio)));
    const row = (p) => Math.min(rows - 1, Math.max(0, Math.floor((p - lo) / step)));
    for (let i = from; i < n; i++) {
      const w = weight[i] * (boost.get(i) || 1);
      if (!(w > 0)) continue;
      const buying = (1 + pressure[i]) / 2, a = row(c[i].low), b = row(c[i].high);
      const span = Math.max(c[i].high - c[i].low, step * 1e-9);
      for (let k = a; k <= b; k++) {
        const overlap = a === b ? 1 : Math.max(0, Math.min(c[i].high, lo + (k + 1) * step) - Math.max(c[i].low, lo + k * step)) / span;
        buy[k] += w * overlap * buying;
        sell[k] += w * overlap * (1 - buying);
      }
    }
    let total = 0;
    for (let k = 0; k < rows; k++) total += buy[k] + sell[k];
    if (!(total > 0)) return [];
    const at = row(c[n - 1].close), below = at - 1, above = at + 1;
    const pick = (demand) => {
      const idx = [];
      if (demand) for (let k = 0; k <= below; k++) idx.push(k); else for (let k = Math.min(above, rows); k < rows; k++) idx.push(k);
      const inSide = new Set(idx), score = new Array(rows).fill(0);
      idx.forEach((k) => { score[k] = Math.max(0, demand ? buy[k] - sell[k] : sell[k] - buy[k]); });
      // Strength: the zone's share of all this side's surplus (of the buyers under the price, the sellers above).
      const sideTotal = idx.reduce((a, k) => a + score[k], 0);
      const used = new Set(), found = [];
      while (found.length < Math.max(count, 1)) {
        let best = null;
        idx.forEach((k) => { if (!used.has(k) && score[k] > 0 && (best === null || score[k] > score[best])) best = k; });
        if (best === null) break;
        // Tight: the strongest row and its strongest neighbours at 80 % of it or more, three rows at most.
        const ok = (k, part) => k >= 0 && k < rows && inSide.has(k) && !used.has(k) && score[k] >= score[best] * part;
        let a = best, b = best;
        while (b - a < 2) {
          const left = ok(a - 1, 0.8) ? score[a - 1] : -1, right = ok(b + 1, 0.8) ? score[b + 1] : -1;
          if (left < 0 && right < 0) break;
          if (left >= right) a--; else b++;
        }
        // The whole area around it (rows half as strong) is used up, so the next zone is somewhere else.
        let ua = a, ub = b;
        while (ok(ua - 1, 0.5)) ua--;
        while (ok(ub + 1, 0.5)) ub++;
        for (let k = Math.max(0, ua - 1); k <= Math.min(rows - 1, ub + 1); k++) used.add(k);
        const bottom = lo + a * step, top = lo + (b + 1) * step;
        let start = from;
        for (let i = from; i < n; i++) if (c[i].low <= top && c[i].high >= bottom) { start = i; break; }
        let sum = 0;
        for (let k = a; k <= b; k++) sum += score[k];
        found.push({ demand, top, bottom, strength: sum / sideTotal, start, peak: lo + (best + 0.5) * step });
      }
      return found;
    };
    return pick(true).concat(pick(false));
  }

  /* ---------- SMT divergence against a related market ---------- */

  /**
   * Two swing highs (lows) in a row where one market makes a higher high (lower low)
   * and the other does not — the app's rule. Bars of `b` are matched to `a` by time.
   */
  /**
   * SMT divergence: two swing highs (or two swing lows) in a row, on the same stretch of candles in both
   * markets, where one market's second high is higher and the other's is lower (lows: one lower, one higher).
   *  - A swing is `swing` bars each side, in each market on its own; the other market's swing must be within
   *    `near` bars of ours (default: `swing` bars; the nearest one).
   *  - The two swings are the top (bottom) of the stretch between them in both markets, so a line never
   *    crosses a bigger high, and they are at most `lookback` bars apart.
   *  - Two SMTs that share a swing (a chain) keep only the newer.
   * `inverse` (DXY): our highs pair with its lows. Confirmed `swing` bars after the second swing. The newest `count`.
   */
  function smt(a, b, opts = {}) {
    const L = Math.max(opts.swing || 5, 1), lookback = opts.lookback || 60, count = opts.count || 3, inverse = !!opts.inverse;
    // The other market's swing may come a few bars before or after ours (up to one swing length).
    const near = opts.near != null ? opts.near : L;
    const n = a.length;
    if (n <= L * 2 + 2 || !b.length) return [];
    const other = new Map(b.map((x) => [x.time, x]));
    const m = a.map((x) => other.get(x.time) || null);
    // Swings: `L` bars each side less extreme (`up`: higher for highs, lower for lows).
    const pivots = (get, up) => {
      const out = [];
      for (let p = L; p < n - L; p++) {
        const v = get(p);
        if (v == null) continue;
        let ok = true;
        for (let j = p - L; j <= p + L && ok; j++) { const w = j === p ? null : get(j); if (w != null && !up(v, w)) ok = false; }
        if (ok) out.push(p);
      }
      return out;
    };
    const out = [];
    for (const high of [true, false]) {
      const A = (i) => (high ? a[i].high : a[i].low);
      const bHigh = high !== inverse;
      const B = (i) => (m[i] ? (bHigh ? m[i].high : m[i].low) : null);
      const pa = pivots(A, (x, y) => (high ? x > y : x < y));
      const pb = pivots(B, (x, y) => (bHigh ? x > y : x < y));
      // Our swings that the other market also made (its nearest swing within `near` bars).
      const pairs = [];
      pa.forEach((i) => {
        let best = null;
        pb.forEach((j) => { if (Math.abs(j - i) <= near && (best == null || Math.abs(j - i) < Math.abs(best - i))) best = j; });
        if (best != null) pairs.push([i, best]);
      });
      for (let k = 1; k < pairs.length; k++) {
        const [i1, j1] = pairs[k - 1], [i2, j2] = pairs[k];
        if (i2 - i1 > lookback || j2 <= j1) continue;
        const a1 = A(i1), a2 = A(i2), b1 = B(j1), b2 = B(j2);
        if (a1 === a2 || b1 === b2) continue;
        const aUp = high ? a2 > a1 : a2 < a1, bUp = bHigh ? b2 > b1 : b2 < b1;
        if (aUp === bUp) continue;
        // Nothing between the two swings beyond them, in either market.
        const aTop = high ? Math.max(a1, a2) : Math.min(a1, a2), bTop = bHigh ? Math.max(b1, b2) : Math.min(b1, b2);
        let clean = true;
        for (let j = Math.min(i1, j1) + 1; j < Math.max(i2, j2) && clean; j++) {
          if (j !== i1 && j !== i2 && (high ? A(j) > aTop : A(j) < aTop)) clean = false;
          const v = B(j);
          if (clean && v != null && j !== j1 && j !== j2 && (bHigh ? v > bTop : v < bTop)) clean = false;
        }
        if (!clean) continue;
        // Chained with the one before (its second swing is this one's first): keep only the newer, so the
        // lines never zigzag from swing to swing.
        const prev = out[out.length - 1];
        if (prev && prev.bull === !high && prev.end === i1) out.pop();
        out.push({ bull: !high, start: i1, end: i2, p1: a1, p2: a2, t1: a[i1].time, t2: a[i2].time,
          b1, b2, bt1: a[j1].time, bt2: a[j2].time, chartHigher: aUp, confirmed: a[Math.min(n - 1, Math.max(i2, j2) + L)].time });
      }
    }
    return out.sort((x, y) => x.end - y.end).slice(-count);
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
      [[x1, y1], [x2, y2]].forEach(([x, y]) => { g.fillStyle = c; g.beginPath(); g.arc(x, y, 2.5, 0, Math.PI * 2); g.fill(); });
      g.fillStyle = c; g.textAlign = "center"; g.textBaseline = d.bull ? "top" : "bottom";
      g.fillText(`SMT ${d.bull ? "tăng" : "giảm"}`, (x1 + x2) / 2, (d.bull ? Math.max(y1, y2) + 4 : Math.min(y1, y2) - 4));
    });
    g.restore();
  }

  /** Shark bubbles like the app: a big buyer under its candle, a big seller above it. */
  /** Shark supply / demand: a band from the zone's first bar to the right (`labels` false, under the candles),
   *  or its "CẦU 4012.50 – 4015.00 · 12%" at the right (`labels` true, over them). */
  function drawZones(g, zones, X, Y, w, up, down, digits, bg = "rgba(21,28,42,.88)", labels = false, avoid = []) {
    if (!zones || !zones.length) return;
    const placed = [];
    const x0 = X(0), x1 = X(1), half = x0 != null && x1 != null ? Math.max(0.5, (x1 - x0) / 2) : 2;
    g.save();
    g.font = "600 10px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
    g.textAlign = "right"; g.textBaseline = "middle";
    zones.forEach((z) => {
      const a = X(z.start), yt = Y(z.top), yb = Y(z.bottom);
      if (a == null || yt == null || yb == null) return;
      const left = Math.max(0, a - half);
      if (left >= w) return;
      const color = z.demand ? up : down;
      if (labels) {
        // At the right on a small backing, so candles and lines under it never hide it.
        const text = `${z.demand ? "CẦU" : "CUNG"} ${z.bottom.toFixed(digits)} – ${z.top.toFixed(digits)} · ${Math.round(z.strength * 100)}%`;
        const tw = g.measureText(text).width;
        let ym = (yt + yb) / 2;
        // Clear of the other zones' names, and left of a trade label at the same height.
        while (placed.some((p) => Math.abs(p - ym) < 17)) ym += 17;
        placed.push(ym);
        const right = avoid.some((y) => Math.abs(y - ym) < 17) ? w - 210 : w - 4;
        g.fillStyle = bg;
        g.beginPath(); g.roundRect(right - tw - 10, ym - 8, tw + 10, 16, 4); g.fill();
        g.strokeStyle = color; g.globalAlpha = 0.7; g.lineWidth = 1; g.stroke(); g.globalAlpha = 1;
        g.fillStyle = color;
        g.fillText(text, right - 5, ym + 0.5);
        return;
      }
      g.globalAlpha = 0.13; g.fillStyle = color;
      g.fillRect(left, yt, w - left, Math.max(2, yb - yt));
      g.globalAlpha = 0.6; g.strokeStyle = color; g.lineWidth = 0.8; g.setLineDash([4, 3]);
      [yt, yb].forEach((y) => { g.beginPath(); g.moveTo(left, Math.round(y) + 0.5); g.lineTo(w, Math.round(y) + 0.5); g.stroke(); });
      g.setLineDash([]); g.globalAlpha = 1;
    });
    g.restore();
  }

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

  window.ICT = { drawSharks, drawZones, defaults, merge, compute, draw, sharkFlow, smt, drawSMT };
})();
