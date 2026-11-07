/* Vùng thanh khoản — where the stops rest, ranked strong / medium.
 * Buy-side liquidity (BSL) sits above highs, sell-side (SSL) under lows. Each pool is a level where these
 * gather, merged when they lie within a hair of each other (an ATR-based tolerance), and scored by what
 * makes it a bigger target (the usual ingredients of liquidity tools):
 *  - equal highs / lows: two or more swing points at the same level (+2, three or more +3);
 *  - a swing of H1 (+1) or H4 (+2);
 *  - yesterday's high / low (+2), last week's (+3);
 *  - a session's high / low (Asia, London, New York: +1, two or more +2);
 *  - a swing made on volume (tick volume, or range when there is none) at least 1.5× its average (+1);
 *  - untouched for over a day (+1);
 *  - a round number (every 100 pips: 10 on gold) (+1).
 * Strong from 5 points, medium 3–4 (weaker ones are left off). A pool is taken (swept) when price trades
 * beyond it; the chart says whether it closed back (a sweep) or went through (a break).
 * Every pool is known only from the bar that confirms it, so the record on the chart has no hindsight. */
(() => {
  "use strict";

  function defaults() {
    return {
      swingLen: 5, tolAtr: 0.3, strong: 5, medium: 3, showMedium: true, showTaken: 3, range: 1.5,
      equal: true, htf: true, days: true, weeks: true, sessions: true, volume: true, age: true, round: true,
      labels: true, panel: true, bsl: "#f23645", ssl: "#089981",
    };
  }
  function merge(saved) {
    const d = defaults();
    if (!saved || typeof saved !== "object") return d;
    Object.keys(d).forEach((k) => { if (saved[k] !== undefined && typeof saved[k] === typeof d[k]) d[k] = saved[k]; });
    return d;
  }

  const DAY = 86400, WEEK = 7 * DAY;
  const pipSize = (p) => (p >= 500 ? 0.1 : p >= 20 ? 0.01 : 0.0001);

  // New York clock (sessions), cached by hour.
  const NYF = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit" });
  const NYC = new Map();
  function ny(t) {
    const hk = Math.floor(t / 3600);
    let v = NYC.get(hk);
    if (!v) {
      const p = Object.fromEntries(NYF.formatToParts(new Date(hk * 3600000)).map((x) => [x.type, x.value]));
      v = { hour: +p.hour % 24, day: `${p.year}-${p.month}-${p.day}` };
      NYC.set(hk, v);
    }
    return { hour: v.hour + (t % 3600) / 3600, day: v.day };
  }
  const SESSIONS = [["Á", 20, 24], ["London", 2, 5], ["New York", 7, 11]];

  function aggregate(bars, sec) {
    const out = [];
    bars.forEach((b) => {
      const t = Math.floor(b.time / sec) * sec, l = out[out.length - 1];
      if (l && l.time === t) { l.high = Math.max(l.high, b.high); l.low = Math.min(l.low, b.low); l.close = b.close; l.volume = (l.volume || 0) + (b.volume || 0); }
      else out.push({ time: t, open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume || 0 });
    });
    return out;
  }
  function avgRange(c, n) {
    const out = new Array(c.length).fill(0);
    let s = 0;
    c.forEach((b, i) => { s += b.high - b.low; if (i >= n) s -= c[i - n].high - c[i - n].low; out[i] = s / Math.min(i + 1, n); });
    return out;
  }
  /** Swing highs / lows of `c` (of `sec`): `len` candles each side; known once those have closed. */
  function swings(c, sec, len) {
    const out = [];
    for (let i = len; i + len < c.length; i++) {
      let h = true, l = true;
      for (let k = 1; k <= len; k++) {
        if (c[i - k].high >= c[i].high || c[i + k].high > c[i].high) h = false;
        if (c[i - k].low <= c[i].low || c[i + k].low < c[i].low) l = false;
      }
      if (h) out.push({ side: 1, price: c[i].high, t: c[i].time, born: c[i + len].time + sec, i });
      if (l) out.push({ side: -1, price: c[i].low, t: c[i].time, born: c[i + len].time + sec, i });
    }
    return out;
  }

  /** Every level that holds liquidity, with where it came from. */
  function levels(bars, sec, cfg, ctx) {
    const n = bars.length, L = [];
    const useVol = bars.some((b) => b.volume > 0);
    const w = bars.map((b) => (useVol ? b.volume : b.high - b.low));
    let ws = 0;
    const wAvg = w.map((x, i) => { ws += x; if (i >= 50) ws -= w[i - 50]; return ws / Math.min(i + 1, 50); });
    swings(bars, sec, Math.max(2, cfg.swingLen | 0)).forEach((s) => {
      const vol = w[s.i] >= (useVol ? 1.5 : 1.8) * (wAvg[s.i] || Infinity);
      L.push({ ...s, src: "swing", vol });
    });
    if (cfg.htf) {
      for (const [list, s, name] of [[ctx.h1, 3600, "H1"], [ctx.h4, 14400, "H4"]]) {
        const c = list && list.length > 10 ? list : aggregate(bars, s);
        swings(c, s, 2).forEach((x) => L.push({ ...x, src: name }));
      }
    }
    const d1 = ctx.d1 && ctx.d1.length > 2 ? ctx.d1 : aggregate(bars, DAY);
    if (cfg.days) d1.forEach((d) => { L.push({ side: 1, price: d.high, t: d.time, born: d.time + DAY, src: "PDH" }); L.push({ side: -1, price: d.low, t: d.time, born: d.time + DAY, src: "PDL" }); });
    if (cfg.weeks) {
      const wk = new Map();
      d1.forEach((d) => { const k = Math.floor((d.time - 4 * DAY) / WEEK); const x = wk.get(k); if (!x) wk.set(k, { t: d.time, high: d.high, low: d.low, end: d.time + DAY }); else { x.high = Math.max(x.high, d.high); x.low = Math.min(x.low, d.low); x.end = d.time + DAY; } });
      [...wk.values()].forEach((x) => { L.push({ side: 1, price: x.high, t: x.t, born: x.end, src: "PWH" }); L.push({ side: -1, price: x.low, t: x.t, born: x.end, src: "PWL" }); });
      // the newest week is still forming: its high / low count only from the next week
      const keys = [...wk.keys()].sort((a, b) => a - b), lastK = keys[keys.length - 1];
      if (lastK != null) L.forEach((x) => { if ((x.src === "PWH" || x.src === "PWL") && Math.floor((x.t - 4 * DAY) / WEEK) === lastK) x.born = Infinity; });
    }
    if (cfg.sessions && sec < 3600) {
      // Session highs / lows from the chart's own bars (in New York time).
      let cur = null;
      const flush = () => { if (cur) { L.push({ side: 1, price: cur.high, t: cur.t, born: cur.end, src: cur.name }); L.push({ side: -1, price: cur.low, t: cur.tl, born: cur.end, src: cur.name }); } cur = null; };
      bars.forEach((b) => {
        const c = ny(b.time), s = SESSIONS.find(([, a, z]) => c.hour >= a && c.hour < z);
        const key = s ? `${c.day}|${s[0]}` : null;
        if (!s || !cur || cur.key !== key) flush();
        if (s) {
          if (!cur) cur = { key, name: `phiên ${s[0]}`, high: b.high, low: b.low, t: b.time, tl: b.time, end: b.time + sec };
          else { if (b.high > cur.high) { cur.high = b.high; cur.t = b.time; } if (b.low < cur.low) { cur.low = b.low; cur.tl = b.time; } cur.end = b.time + sec; }
        }
      });
      // the session still running is not a level yet
      cur = null;
    }
    return L.filter((x) => isFinite(x.born));
  }

  function compute(bars, sec, cfg, ctx = {}) {
    if (!bars || bars.length < 30) return null;
    const n = bars.length, last = bars[n - 1], now = last.time + sec;
    const rng = avgRange(bars, 14), atr = rng[n - 1] || 1;
    const tol = Math.max(atr * (+cfg.tolAtr || 0.3), pipSize(last.close) * 2);
    const L = levels(bars, sec, cfg, ctx).filter((x) => x.born <= now).sort((a, b) => a.born - b.born);
    // Pools: levels of a side within `tol` of each other, merged in the order they became known; a pool
    // taken before the next level joins it ends, and that level starts a new pool.
    const pools = [];
    const timeIdx = (t) => { let lo = 0, hi = n - 1; while (lo < hi) { const m = (lo + hi) >> 1; if (bars[m].time < t) lo = m + 1; else hi = m; } return lo; };
    // Taken: a bar trading more than the tolerance beyond it (equal highs a hair apart stay one pool).
    const scan = (p, fromT) => {
      p.taken = null;
      for (let k = timeIdx(fromT); k < n; k++) {
        const b = bars[k];
        if (p.side > 0 ? b.high > p.price + tol : b.low < p.price - tol) { p.taken = b.time; p.takenIdx = k; p.reclaimed = p.side > 0 ? b.close < p.price : b.close > p.price; return; }
      }
    };
    for (const x of L) {
      // A pool still there when this level became known (not taken before it).
      let p = null;
      for (const q of pools) if (q.side === x.side && (q.taken == null || q.taken > x.born) && Math.abs(q.price - x.price) <= tol) { p = q; break; }
      if (!p) { p = { side: x.side, price: x.price, from: x.t, born: x.born, src: [] }; pools.push(p); }
      p.src.push(x);
      p.price = x.side > 0 ? Math.max(p.price, x.price) : Math.min(p.price, x.price);
      p.born = Math.max(p.born, x.born); p.from = Math.min(p.from, x.t);
      scan(p, p.born);
    }
    // Score each pool.
    const step = pipSize(last.close) * 100;
    pools.forEach((p) => {
      const why = [];
      let s = 0;
      const sw = p.src.filter((x) => x.src === "swing").length;
      if (cfg.equal && sw >= 3) { s += 3; why.push(`${sw} ${p.side > 0 ? "đỉnh" : "đáy"} bằng`); } else if (cfg.equal && sw === 2) { s += 2; why.push(`2 ${p.side > 0 ? "đỉnh" : "đáy"} bằng`); }
      if (p.src.some((x) => x.src === "H4")) { s += 2; why.push("swing H4"); } else if (p.src.some((x) => x.src === "H1")) { s += 1; why.push("swing H1"); }
      if (p.src.some((x) => x.src === "PWH" || x.src === "PWL")) { s += 3; why.push(p.side > 0 ? "đỉnh tuần trước" : "đáy tuần trước"); }
      if (p.src.some((x) => x.src === "PDH" || x.src === "PDL")) { s += 2; why.push(p.side > 0 ? "đỉnh ngày (PDH)" : "đáy ngày (PDL)"); }
      const ses = [...new Set(p.src.filter((x) => x.src.startsWith("phiên")).map((x) => x.src))];
      if (ses.length) { s += Math.min(2, ses.length); why.push(ses.join(", ")); }
      if (cfg.volume && p.src.some((x) => x.vol)) { s += 1; why.push("khối lượng lớn"); }
      const end = p.taken != null ? p.taken : now;
      if (cfg.age && end - p.born > DAY) { s += 1; why.push("> 1 ngày chưa bị quét"); }
      if (cfg.round && Math.abs(p.price - Math.round(p.price / step) * step) <= tol) { s += 1; why.push("số tròn"); }
      p.score = s; p.why = why;
      p.grade = s >= cfg.strong ? "strong" : s >= cfg.medium ? "medium" : null;
    });
    // Shown: untaken pools within `range` days' worth of range from price, and the last few taken.
    const dRange = (() => { const d = aggregate(bars.slice(-Math.min(n, Math.round(5 * DAY / sec))), DAY); return d.length ? d.reduce((a, c) => a + c.high - c.low, 0) / d.length : atr * 50; })();
    const near = (p) => Math.abs(p.price - last.close) <= dRange * (+cfg.range || 3);
    const live = pools.filter((p) => p.grade && p.taken == null && near(p) && (cfg.showMedium || p.grade === "strong"));
    const taken = pools.filter((p) => p.grade && p.taken != null && (cfg.showMedium || p.grade === "strong")).sort((a, b) => b.taken - a.taken).slice(0, Math.max(0, cfg.showTaken | 0));
    const out = { sec, tol, pools: [...live, ...taken], all: pools, lastIdx: n - 1, lastTime: last.time };
    const above = live.filter((p) => p.side > 0 && p.price > last.close).sort((a, b) => a.price - b.price);
    const below = live.filter((p) => p.side < 0 && p.price < last.close).sort((a, b) => b.price - a.price);
    const pip = pipSize(last.close), f = ctx.fmt || ((v) => v.toFixed(2));
    const say = (p) => `${p.grade === "strong" ? "MẠNH" : "vừa"} ${f(p.price)} (${Math.round(Math.abs(p.price - last.close) / pip)} pip)`;
    // The nearest pool on each side, and the nearest strong one when that is farther.
    const pick = (list) => { const a = list[0], st = list.find((p) => p.grade === "strong"); return [a, st && st !== a ? st : null].filter(Boolean); };
    out.lines = [
      { text: `Thanh khoản trên (BSL): ${above.length ? pick(above).map(say).join(" · ") : "—"}`, dir: 1 },
      { text: `Thanh khoản dưới (SSL): ${below.length ? pick(below).map(say).join(" · ") : "—"}`, dir: -1 },
    ];
    const lt = taken[0];
    if (lt) out.lines.push({ text: `Vừa bị lấy: ${lt.side > 0 ? "BSL" : "SSL"} ${lt.grade === "strong" ? "mạnh" : "vừa"} ${f(lt.price)} → ${lt.reclaimed ? "quét rồi đóng lại (có thể đảo chiều)" : "phá qua (có thể đi tiếp)"}`, dir: 0 });
    return out;
  }

  /* ----- drawing ----- */

  function rgba(hex, a) {
    const h = (hex || "#787b86").replace("#", "");
    return `rgba(${parseInt(h.slice(0, 2), 16)}, ${parseInt(h.slice(2, 4), 16)}, ${parseInt(h.slice(4, 6), 16)}, ${a})`;
  }

  function draw(g, o, cfg, T, Y, w, h, fmt) {
    if (!o) return;
    fmt = fmt || ((v) => v.toFixed(2));
    g.save();
    g.font = "600 10.5px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif"; g.textBaseline = "middle";
    const labels = [];
    o.pools.forEach((p) => {
      const strong = p.grade === "strong", c = p.side > 0 ? cfg.bsl : cfg.ssl, taken = p.taken != null;
      const y = Y(p.price), yb = Y(p.side > 0 ? p.price - o.tol : p.price + o.tol);
      if (y == null || yb == null) return;
      const x0 = Math.max(0, T(p.from) ?? 0), x1 = taken ? (T(p.taken) ?? w) : w;
      if (x1 < 0) return;
      const top = Math.min(y, yb), hgt = Math.max(strong ? 4 : 2, Math.abs(yb - y));
      g.globalAlpha = taken ? 0.45 : 1;
      g.fillStyle = rgba(c, strong ? 0.22 : 0.1); g.fillRect(x0, top, x1 - x0, hgt);
      g.strokeStyle = rgba(c, strong ? 0.95 : 0.6); g.lineWidth = strong ? 1.6 : 1; g.setLineDash(strong ? [] : [5, 4]);
      g.beginPath(); g.moveTo(x0, Math.round(y) + 0.5); g.lineTo(x1, Math.round(y) + 0.5); g.stroke(); g.setLineDash([]);
      // Each source as a small tick where it formed.
      g.fillStyle = c;
      p.src.forEach((s) => { const x = T(s.t); if (x != null && x >= x0 && x <= x1) { g.beginPath(); g.arc(x, y, s.src === "swing" ? 2.2 : 3, 0, Math.PI * 2); g.fill(); } });
      if (taken) {
        g.fillStyle = c; g.textAlign = "left";
        g.fillText(p.reclaimed ? "✓ quét" : "✕ phá", x1 + 4, y + (p.side > 0 ? -8 : 8));
      } else if (cfg.labels) labels.push({ y, text: `${p.side > 0 ? "BSL" : "SSL"} ${strong ? "MẠNH" : "vừa"} · ${p.why.slice(0, 3).join(" · ")} · ${fmt(p.price)}`, c, strong });
      g.globalAlpha = 1;
    });
    // Labels on the right, kept apart.
    labels.sort((a, b) => a.y - b.y);
    let lastY = -Infinity;
    labels.forEach((l) => {
      const y = Math.max(l.y - 8, lastY + 15);
      lastY = y;
      const tw = g.measureText(l.text).width + 10, x = w - tw - 6;
      g.fillStyle = l.strong ? rgba(l.c, 0.9) : "rgba(21, 28, 42, 0.8)";
      g.beginPath(); g.roundRect(x, y - 7, tw, 14, 4); g.fill();
      g.fillStyle = l.strong ? "#ffffff" : l.c; g.textAlign = "left"; g.fillText(l.text, x + 5, y + 0.5);
    });
    g.restore();
  }

  /** A small box under the trade buttons (top left): the nearest pools above and below. */
  function drawPanel(g, o, cfg, w, h) {
    if (!o || !cfg.panel || !o.lines) return;
    g.save();
    g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif"; g.textBaseline = "middle";
    const lh = 17, pad = 8, bw = Math.min(w - 20, Math.max(...o.lines.map((l) => g.measureText(l.text).width)) + pad * 2 + 12), bh = o.lines.length * lh + pad * 2 - 4;
    const bx = 10, by = 136;
    g.fillStyle = "rgba(15, 20, 30, 0.9)"; g.beginPath(); g.roundRect(bx, by, bw, bh, 8); g.fill();
    o.lines.forEach((l, i) => {
      const y = by + pad + i * lh + 6;
      g.fillStyle = l.dir > 0 ? cfg.bsl : l.dir < 0 ? cfg.ssl : "#c9d1dc";
      g.beginPath(); g.arc(bx + pad + 3, y, 3, 0, Math.PI * 2); g.fill();
      g.fillStyle = "#e8ecf3"; g.textAlign = "left"; g.fillText(l.text, bx + pad + 12, y + 0.5);
    });
    g.restore();
  }

  window.LIQ = { defaults, merge, compute, draw, drawPanel };
})();
