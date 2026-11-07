/* Kế hoạch giao dịch — the owner's own way of trading, top down:
 *  1. Day: the plan from yesterday's candle (next candle model): where price is headed, or which of
 *     yesterday's high / low it should sweep first; yesterday's high / low / close and today's open.
 *  2. H4: where the H4 candles close around the day's open (above → up, below → down).
 *  3. H1 / H4: the fair value gaps and order blocks still open, where price may turn (entries).
 *  4. Trend: a trendline through three highs (falling) or three lows (rising) on a higher timeframe of
 *     the chart, and its breakout, judged real (holds beyond) or fake (closes back inside).
 *  5. Entry on the chart (M1 / M5): a rejection candle (long wick, close back) at the trendline, after a
 *     fake breakout, at the retest of a real one, at an H1 / H4 zone in the trend's direction, or at a
 *     sweep of yesterday's high / low. Stop beyond the wick (50 pips at most); with the day's bias the
 *     target is the next liquidity (hold longer), against it 1R (short).
 * Every level and signal at a bar is worked out from the bars up to that bar only. */
(() => {
  "use strict";

  function defaults() {
    return {
      levels: true, h4: true, zones: true, zoneCount: 2, trend: true, trendTf: "auto", touches: 3, fakeBars: 3,
      // Only the retest of a real breakout held up in the backtest (gold, April to November 2026); the others
      // are there to be turned on and checked against the record on the chart.
      signals: true, sigTrend: false, sigFake: false, sigRetest: true, sigZone: false, sigSweep: false,
      maxSlPips: 50, minSlPips: 10, spread: 0.3, tpWith: 3, tpAgainst: 1, tpNeutral: 2, signalCount: 6, panel: true,
      bull: "#089981", bear: "#f23645", level: "#2962ff", zoneBuy: "#089981", zoneSell: "#f23645", trendColor: "#ff9800",
    };
  }

  function merge(saved) {
    const d = defaults();
    if (!saved || typeof saved !== "object") return d;
    Object.keys(d).forEach((k) => { if (saved[k] !== undefined && typeof saved[k] === typeof d[k]) d[k] = saved[k]; });
    return d;
  }

  const DAY = 86400;
  const pipSize = (p) => (p >= 500 ? 0.1 : p >= 20 ? 0.01 : 0.0001);
  const TF_NAME = (s) => (s < 3600 ? `${s / 60}m` : s < DAY ? `H${s / 3600}` : "D1");

  /** Bars of `sec` built from bars of `base` (each with the index range it covers). */
  function aggregate(bars, sec) {
    const out = [];
    bars.forEach((b, i) => {
      const t = Math.floor(b.time / sec) * sec, last = out[out.length - 1];
      if (last && last.time === t) { last.high = Math.max(last.high, b.high); last.low = Math.min(last.low, b.low); last.close = b.close; last.end = i; }
      else out.push({ time: t, open: b.open, high: b.high, low: b.low, close: b.close, start: i, end: i });
    });
    return out;
  }

  function avgRange(bars, n) {
    const out = new Array(bars.length).fill(0);
    let sum = 0;
    bars.forEach((b, i) => { sum += b.high - b.low; if (i >= n) sum -= bars[i - n].high - bars[i - n].low; out[i] = sum / Math.min(i + 1, n); });
    return out;
  }

  /** The last completed candle of `list` (sorted, of `sec`) before time `t`: its index, or -1. */
  function doneBefore(list, sec, t) {
    let lo = 0, hi = list.length - 1, ans = -1;
    while (lo <= hi) { const m = (lo + hi) >> 1; if (list[m].time + sec <= t) { ans = m; lo = m + 1; } else hi = m - 1; }
    return ans;
  }

  /* ----- 1. the day ----- */

  /** The plan from yesterday's candle against the day before (next candle model). */
  function dayPlan(d1, t) {
    const k = doneBefore(d1, DAY, t);
    if (k < 1) return null;
    const y = d1[k], b = d1[k - 1], today = d1[k + 1] && d1[k + 1].time <= t ? d1[k + 1] : null;
    let bias = 0, why;
    if (y.close > b.high) { bias = 1; why = "hôm qua đóng trên đỉnh hôm kia → tiếp diễn tăng"; }
    else if (y.close < b.low) { bias = -1; why = "hôm qua đóng dưới đáy hôm kia → tiếp diễn giảm"; }
    else if (y.high > b.high && y.close < b.high) { bias = -1; why = "hôm qua quét đỉnh hôm kia rồi đóng lại dưới → đảo chiều giảm"; }
    else if (y.low < b.low && y.close > b.low) { bias = 1; why = "hôm qua quét đáy hôm kia rồi đóng lại trên → đảo chiều tăng"; }
    else why = "hôm qua là nến trong (inside) → chờ quét đỉnh hoặc đáy hôm qua";
    return { bias, why, pdh: y.high, pdl: y.low, pdc: y.close, dayOpen: today ? today.open : null, dayStart: y.time + DAY, today, y };
  }

  /* ----- 3. zones: H1 / H4 fair value gaps and order blocks ----- */

  /** Zones of candles `c` (of `sec`): born when the candle that makes them closes, dead at a close through
   *  the far side (on those candles). dir +1 = buy zone (under price), -1 = sell zone. */
  function zonesOf(c, sec, tf) {
    const out = [];
    for (let k = 2; k < c.length; k++) {
      const a = c[k - 2], m = c[k - 1], z = c[k];
      if (z.low > a.high) out.push({ dir: 1, kind: "FVG", tf, top: z.low, bottom: a.high, born: z.time + sec, from: m.time });
      if (z.high < a.low) out.push({ dir: -1, kind: "FVG", tf, top: a.low, bottom: z.high, born: z.time + sec, from: m.time });
      // Order block: the last opposite candle before a candle that closes beyond its whole range.
      if (m.close < m.open && z.close > m.high) out.push({ dir: 1, kind: "OB", tf, top: m.high, bottom: m.low, born: z.time + sec, from: m.time });
      if (m.close > m.open && z.close < m.low) out.push({ dir: -1, kind: "OB", tf, top: m.high, bottom: m.low, born: z.time + sec, from: m.time });
    }
    out.forEach((g) => {
      g.dead = Infinity;
      for (let k = 0; k < c.length; k++) {
        if (c[k].time < g.born) continue;
        if (g.dir > 0 ? c[k].close < g.bottom : c[k].close > g.top) { g.dead = c[k].time + sec; break; }
      }
    });
    return out;
  }

  /* ----- 4. trendlines through three highs / lows ----- */

  /** Lines on candles `c` (of `sec`): falling through ≥ `touches` swing highs (dir -1, price under it) or
   *  rising through ≥ `touches` swing lows (dir +1). Price as a function of time. With its breakout: the
   *  first close beyond, "fake" when a close comes back inside within `fakeBars` candles, else "real". */
  function trendlines(c, sec, touches, fakeBars) {
    const n = c.length, len = 2;
    if (n < 30) return [];
    const rng = avgRange(c, 14), hi = [], lo = [];
    for (let i = len; i + len < n; i++) {
      let h = true, l = true;
      for (let k = 1; k <= len; k++) {
        if (c[i - k].high >= c[i].high || c[i + k].high > c[i].high) h = false;
        if (c[i - k].low <= c[i].low || c[i + k].low < c[i].low) l = false;
      }
      if (h) hi.push(i);
      if (l) lo.push(i);
    }
    const out = [];
    for (const dir of [-1, 1]) {
      const piv = dir < 0 ? hi : lo, val = (i) => (dir < 0 ? c[i].high : c[i].low);
      const found = [], seen = new Set();
      for (let a = 0; a < piv.length; a++) for (let b = a + 1; b < piv.length && piv[b] - piv[a] <= 200; b++) {
        const ia = piv[a], ib = piv[b];
        if (ib - ia < 3) continue;
        if (dir < 0 ? val(ib) >= val(ia) : val(ib) <= val(ia)) continue;
        const slope = (val(ib) - val(ia)) / (c[ib].time - c[ia].time), at = (i) => val(ia) + slope * (c[i].time - c[ia].time);
        // Touches: swing points on the line (a hair either side); no close through it up to the last one.
        const pts = [ia, ib];
        let ok = true, last = ib;
        for (let x = b + 1; x < piv.length && piv[x] - ia <= 300; x++) {
          const ix = piv[x], tol = rng[ix] * 0.35;
          if (Math.abs(val(ix) - at(ix)) <= tol) { pts.push(ix); last = ix; }
        }
        if (pts.length < touches) continue;
        const key = `${ia}-${last}`;
        if (seen.has(key)) continue;
        seen.add(key);
        for (let i = ia + 1; i <= last && ok; i++) if (dir < 0 ? c[i].close > at(i) + rng[i] * 0.1 : c[i].close < at(i) - rng[i] * 0.1) ok = false;
        if (!ok) continue;
        // Confirmed once the last touch is a confirmed swing point.
        const line = { dir, t0: c[ia].time, p0: val(ia), slope, pts: pts.map((i) => ({ t: c[i].time, p: val(i) })), born: c[last + len].time + sec, lastTouch: c[last].time };
        line.price = (t) => line.p0 + line.slope * (t - line.t0);
        // The breakout: the first close beyond after the last touch.
        for (let i = last + 1; i < n; i++) {
          if (dir < 0 ? c[i].close > at(i) + rng[i] * 0.1 : c[i].close < at(i) - rng[i] * 0.1) {
            line.breakAt = c[i].time + sec; line.breakBar = c[i].time;
            let back = null;
            for (let k = i + 1; k < n && k <= i + fakeBars; k++) if (dir < 0 ? c[k].close < at(k) : c[k].close > at(k)) { back = k; break; }
            if (back != null) { line.breakType = "fake"; line.judged = c[back].time + sec; line.fakeExt = dir < 0 ? Math.max(...c.slice(i, back + 1).map((x) => x.high)) : Math.min(...c.slice(i, back + 1).map((x) => x.low)); }
            else if (i + fakeBars < n) { line.breakType = "real"; line.judged = c[i + fakeBars].time + sec; }
            else line.breakType = "pending";
            break;
          }
        }
        found.push(line);
      }
      out.push(...found);
    }
    return out.sort((x, y) => x.born - y.born);
  }

  /** The lines to draw: the newest ones that do not repeat each other (newest last touch, most touches). */
  function shownLines(all, sec, rng, max) {
    const kept = [];
    for (const l of all.slice().sort((x, y) => y.lastTouch - x.lastTouch || y.pts.length - x.pts.length)) {
      if (kept.some((k) => k.dir === l.dir && (Math.abs(k.lastTouch - l.lastTouch) < sec * 6 || Math.abs(k.price(l.lastTouch) - l.price(l.lastTouch)) < rng))) continue;
      kept.push(l);
      if (kept.filter((k) => k.dir === l.dir).length >= max) break;
    }
    return kept;
  }

  /* ----- 5. entries ----- */

  /** A rejection candle: the wick toward `dir`'s stop at least twice the body and half the range, and the
   *  close in the 40 % of the range away from it. +1: lower wick (buy), -1: upper wick (sell). */
  function rejection(b) {
    const r = b.high - b.low;
    if (!(r > 0)) return 0;
    const body = Math.abs(b.close - b.open), lw = Math.min(b.open, b.close) - b.low, uw = b.high - Math.max(b.open, b.close);
    if (lw >= 2 * body && lw >= 0.5 * r && b.close >= b.low + 0.6 * r) return 1;
    if (uw >= 2 * body && uw >= 0.5 * r && b.close <= b.high - 0.6 * r) return -1;
    return 0;
  }

  const KIND = { trend: "chạm trend", fake: "breakout giả", retest: "retest breakout thật", zone: "vùng H1/H4", sweep: "quét đỉnh/đáy hôm qua" };

  function compute(bars, sec, cfg, ctx = {}) {
    if (!bars || bars.length < 30) return null;
    const n = bars.length, last = bars[n - 1], now = last.time + sec;
    const fmt = ctx.fmt || ((v) => v.toFixed(2));
    const d1 = ctx.d1 && ctx.d1.length > 2 ? ctx.d1 : aggregate(bars, DAY);
    const h4 = ctx.h4 && ctx.h4.length > 2 ? ctx.h4 : aggregate(bars, 14400);
    const h1 = ctx.h1 && ctx.h1.length > 2 ? ctx.h1 : aggregate(bars, 3600);
    const out = { sec, lastIdx: n - 1, lines: [] };
    out.plan = dayPlan(d1, now);
    // H4 around the day's open: the last H4 of yesterday and the H4s of today so far.
    if (out.plan) {
      const k = doneBefore(h4, 14400, now);
      const around = h4.slice(0, k + 1).filter((c) => c.time >= out.plan.dayStart - 14400).slice(-3);
      out.h4 = around.map((c) => ({ time: c.time, close: c.close, open: c.open, side: out.plan.dayOpen == null ? 0 : c.close > out.plan.dayOpen ? 1 : c.close < out.plan.dayOpen ? -1 : 0 }));
    }
    // Zones of H1 and H4.
    const zones = [...zonesOf(h1, 3600, "H1"), ...zonesOf(h4, 14400, "H4")];
    out.zones = zones.filter((z) => z.born <= now && z.dead > now)
      .sort((a, b) => Math.abs((a.top + a.bottom) / 2 - last.close) - Math.abs((b.top + b.bottom) / 2 - last.close));
    // Trendlines on the higher timeframe of the chart.
    const tSec = cfg.trendTf && cfg.trendTf !== "auto" ? +cfg.trendTf : sec <= 60 ? 900 : sec <= 300 ? 3600 : sec <= 900 ? 14400 : sec * 4;
    out.trendSec = Math.max(tSec, sec);
    const tc = aggregate(bars, out.trendSec).map((c) => ({ ...c }));
    // Only completed candles of that timeframe draw lines (the forming one can still change).
    const tcDone = tc.filter((c) => c.time + out.trendSec <= now);
    const allLines = trendlines(tcDone, out.trendSec, Math.max(2, +cfg.touches || 3), Math.max(1, +cfg.fakeBars || 3));
    const tr = avgRange(tcDone.length ? tcDone : bars, 14);
    out.trends = shownLines(allLines.filter((l) => l.lastTouch >= now - 3 * DAY), out.trendSec, tr[tr.length - 1] * 0.5, 2);
    out.lastTime = last.time;
    out.signals = signalsOf(bars, sec, cfg, { d1, h4, zones, trends: allLines, fmt });
    out.lines = panelLines(out, cfg, fmt, last);
    return out;
  }

  function signalsOf(bars, sec, cfg, { d1, h4, zones, trends }) {
    const n = bars.length, rng = avgRange(bars, 14), out = [];
    const pip = pipSize(bars[n - 1].close), cap = (+cfg.maxSlPips || 50) * pip, spread = +cfg.spread || 0;
    let busy = -1, tp = 0;
    const pool = [];
    for (let i = 20; i < n - 1; i++) {
      if (i <= busy) continue;
      const b = bars[i], t = b.time + sec;
      // The lines known by now: confirmed, touched in the last three days, not broken more than a day ago.
      while (tp < trends.length && trends[tp].born <= t) pool.push(trends[tp++]);
      if (pool.length > 400) { const keep = pool.filter((l) => l.lastTouch >= t - 3 * DAY); pool.length = 0; pool.push(...keep); }
      const d = rejection(b);
      if (!d) continue;
      const tol = rng[i] * 0.5;
      const plan = dayPlan(d1, t);
      const live = pool.filter((l) => l.lastTouch >= t - 3 * DAY && !(l.breakAt != null && l.breakAt < t - DAY));
      let kind = null, why = "";
      // A trend must be there: a line in the trade's direction, still holding (or broken and judged).
      for (const l of live) {
        const lp = l.price(b.time);
        const broken = l.breakAt != null && l.breakAt <= t;
        const judged = l.judged != null && l.judged <= t;
        if (!broken && cfg.sigTrend && l.dir === d && (d < 0 ? b.high >= lp - tol && b.close < lp : b.low <= lp + tol && b.close > lp)) { kind = "trend"; why = `chạm trend ${l.pts.length} ${d < 0 ? "đỉnh" : "đáy"}`; break; }
        if (judged && l.breakType === "fake" && cfg.sigFake && l.dir === d && t - l.judged <= 3 * sec * 30 && (d < 0 ? b.high >= lp - tol : b.low <= lp + tol)) { kind = "fake"; why = `breakout giả trend ${l.pts.length} ${d < 0 ? "đỉnh" : "đáy"}`; break; }
        if (judged && l.breakType === "real" && cfg.sigRetest && l.dir === -d && t - l.judged <= 120 * sec && (d > 0 ? b.low <= lp + tol && b.close > lp : b.high >= lp - tol && b.close < lp)) { kind = "retest"; why = `retest breakout thật trend ${l.pts.length} ${d > 0 ? "đỉnh" : "đáy"}`; break; }
      }
      const trendDir = live.filter((l) => !(l.breakAt != null && l.breakAt <= t)).map((l) => l.dir);
      if (!kind && cfg.sigZone && trendDir.includes(d)) {
        const z = zones.find((g) => g.dir === d && g.born <= t && g.dead > t && (d > 0 ? b.low <= g.top && b.low >= g.bottom - tol : b.high >= g.bottom && b.high <= g.top + tol));
        if (z) { kind = "zone"; why = `${z.kind} ${z.tf} + trend`; }
      }
      if (!kind && cfg.sigSweep && plan && (d < 0 ? b.high > plan.pdh && b.close < plan.pdh : b.low < plan.pdl && b.close > plan.pdl)) { kind = "sweep"; why = d < 0 ? "quét đỉnh hôm qua (PDH)" : "quét đáy hôm qua (PDL)"; }
      if (!kind) continue;
      const entry = bars[i + 1].open, stop = d > 0 ? b.low - spread : b.high + spread, risk = (entry - stop) * d;
      if (risk < (+cfg.minSlPips || 0) * pip || risk > cap) continue;
      // Target: with the day's bias the next liquidity of yesterday / today (2R at least, hold longer);
      // against it 1R (short); no bias 1.5R.
      const withBias = plan && plan.bias === d, against = plan && plan.bias === -d;
      const tR = (k) => entry + d * risk * k;
      let target = tR(against ? cfg.tpAgainst : cfg.tpNeutral), tpWhy = against ? `${cfg.tpAgainst}R (ngược bias)` : `${cfg.tpNeutral}R`;
      if (withBias) {
        // Hold longer: the nearest liquidity of yesterday / today between 2R and the cap, else the cap.
        const liq = [plan.pdh, plan.pdl, plan.today ? plan.today.high : null, plan.today ? plan.today.low : null]
          .filter((v) => v != null && (v - entry) * d >= 2 * risk && (v - entry) * d <= cfg.tpWith * risk);
        if (liq.length) { target = d > 0 ? Math.min(...liq) : Math.max(...liq); tpWhy = "thanh khoản ngày (gồng)"; }
        else { target = tR(cfg.tpWith); tpWhy = `${cfg.tpWith}R (thuận bias, gồng)`; }
      }
      let exit = null, exitAt = null, res = "time";
      for (let k = i + 1; k < n && k <= i + 1 + 480; k++) {
        const x = bars[k];
        if (d > 0 ? x.low <= stop : x.high >= stop) { exit = stop; exitAt = k; res = "stop"; break; }
        if (d > 0 ? x.high >= target : x.low <= target) { exit = target; exitAt = k; res = "target"; break; }
      }
      if (exit == null) { exitAt = Math.min(n - 1, i + 481); exit = bars[exitAt].close; if (exitAt === n - 1) res = "open"; }
      const r = ((exit - entry) * d) / risk - spread / risk;
      // H4 against the day's open (the last H4 closed by now) and the size of the rejection candle.
      let h4side = 0;
      if (h4 && plan && plan.dayOpen != null) { const k = doneBefore(h4, 14400, t); if (k >= 0 && h4[k].time >= plan.dayStart - 14400) h4side = Math.sign(h4[k].close - plan.dayOpen); }
      out.push({ h4side, size: (b.high - b.low) / (rng[i] || 1), zoneTf: kind === "zone" ? why.split(" ")[1] : null, hour: new Date(b.time * 1000).getUTCHours(), dir: d, kind, why, at: i + 1, signal: i, time: bars[i + 1].time, entry, stop, target, risk, pips: Math.round(risk / pip), tpWhy, bias: withBias ? "thuận" : against ? "ngược" : "trung tính", exit, exitAt, res, r });
      busy = exitAt;
    }
    return out;
  }

  function panelLines(o, cfg, fmt, last) {
    const L = [], p = o.plan;
    if (p) {
      L.push({ text: `NGÀY: ${p.bias > 0 ? "TĂNG" : p.bias < 0 ? "GIẢM" : "ĐI NGANG"} — ${p.why}`, dir: p.bias });
      const swH = p.today && p.today.high > p.pdh, swL = p.today && p.today.low < p.pdl;
      const plan = p.bias > 0 ? (swL ? `đã quét PDL ${fmt(p.pdl)} → tìm mua, mục tiêu PDH ${fmt(p.pdh)}` : `chờ giá về vùng mua (hoặc quét PDL ${fmt(p.pdl)}) → mục tiêu PDH ${fmt(p.pdh)}`)
        : p.bias < 0 ? (swH ? `đã quét PDH ${fmt(p.pdh)} → tìm bán, mục tiêu PDL ${fmt(p.pdl)}` : `chờ giá lên vùng bán (hoặc quét PDH ${fmt(p.pdh)}) → mục tiêu PDL ${fmt(p.pdl)}`)
          : `chờ quét PDH ${fmt(p.pdh)} để bán hoặc PDL ${fmt(p.pdl)} để mua`;
      L.push({ text: `Kế hoạch: ${plan}`, dir: 0 });
    } else L.push({ text: "NGÀY: chưa đủ nến ngày để lập kế hoạch", dir: 0 });
    if (cfg.h4 && o.h4 && o.h4.length && p && p.dayOpen != null) {
      const s = o.h4.map((c) => `${new Date(c.time * 1000).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })} ${c.side > 0 ? "▲" : c.side < 0 ? "▼" : "="}`).join(" · ");
      const lastSide = o.h4[o.h4.length - 1].side;
      L.push({ text: `H4 so với giá mở ngày ${fmt(p.dayOpen)}: ${s} → ${lastSide > 0 ? "nghiêng TĂNG" : lastSide < 0 ? "nghiêng GIẢM" : "chưa rõ"}`, dir: lastSide });
    }
    if (cfg.zones && o.zones && o.zones.length) {
      const buy = o.zones.find((z) => z.dir > 0 && z.top < last.close), sell = o.zones.find((z) => z.dir < 0 && z.bottom > last.close);
      L.push({ text: `H1/H4: ${buy ? `mua ở ${buy.kind} ${buy.tf} ${fmt(buy.bottom)}–${fmt(buy.top)}` : "chưa có vùng mua bên dưới"} · ${sell ? `bán ở ${sell.kind} ${sell.tf} ${fmt(sell.bottom)}–${fmt(sell.top)}` : "chưa có vùng bán bên trên"}`, dir: 0 });
    }
    if (cfg.trend) {
      const tf = TF_NAME(o.trendSec), act = o.trends.filter((l) => l.breakAt == null), lastBo = o.trends.filter((l) => l.breakAt != null).sort((a, b) => b.breakAt - a.breakAt)[0];
      const s = act.length ? act.slice(0, 2).map((l) => `${l.dir < 0 ? "giảm" : "tăng"} (${l.pts.length} ${l.dir < 0 ? "đỉnh" : "đáy"}) ở ${fmt(l.price(last.time))}`).join(", ") : "chưa có trend 3 chạm";
      L.push({ text: `Trend ${tf}: ${s}${lastBo ? ` · breakout gần nhất: ${lastBo.breakType === "fake" ? "GIẢ" : lastBo.breakType === "real" ? "THẬT" : "đang xét"}` : ""}`, dir: act.length ? act[0].dir : 0 });
    }
    const sig = o.signals || [], cur = sig[sig.length - 1];
    if (cur) {
      const side = cur.dir > 0 ? "MUA" : "BÁN";
      L.push({ text: `${cur.res === "open" ? "ĐANG" : "Tín hiệu gần nhất:"} ${side} ${fmt(cur.entry)} (${KIND[cur.kind]}, ${cur.bias} bias) · SL ${fmt(cur.stop)} (${cur.pips} pip) · TP ${fmt(cur.target)} ${cur.tpWhy}${cur.res !== "open" ? ` → ${cur.r >= 0 ? "+" : ""}${cur.r.toFixed(1)}R` : ""}`, dir: cur.dir });
    }
    const done = sig.filter((s) => s.res !== "open");
    if (done.length) {
      const w = done.filter((s) => s.r > 0).length, R = done.reduce((a, s) => a + s.r, 0);
      L.push({ text: `Trên chart: ${done.length} lệnh · ${w} thắng / ${done.length - w} thua (${Math.round((w / done.length) * 100)}%) · ${R >= 0 ? "+" : ""}${R.toFixed(1)}R`, dir: R > 0 ? 1 : R < 0 ? -1 : 0 });
    }
    return L;
  }

  /* ----- drawing ----- */

  const FONT = "600 10.5px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
  function rgba(hex, a) {
    const h = (hex || "#787b86").replace("#", "");
    return `rgba(${parseInt(h.slice(0, 2), 16)}, ${parseInt(h.slice(2, 4), 16)}, ${parseInt(h.slice(4, 6), 16)}, ${a})`;
  }
  function pill(g, text, x, y, bg, align = "left") {
    const tw = g.measureText(text).width, pw = tw + 10, ph = 16, x0 = align === "right" ? x - pw : align === "center" ? x - pw / 2 : x;
    g.fillStyle = bg; g.beginPath(); g.roundRect(x0, y - ph / 2, pw, ph, 4); g.fill();
    g.fillStyle = "#ffffff"; g.textAlign = "left"; g.fillText(text, x0 + 5, y + 0.5);
  }

  /** `T(time)` gives x for a time (past the last bar too), `Y(price)` y. */
  function draw(g, o, cfg, T, X, Y, w, h, fmt) {
    if (!o) return;
    fmt = fmt || ((v) => v.toFixed(2));
    g.save(); g.font = FONT; g.textBaseline = "middle";
    const hl = (price, x0, x1, color, dash, label) => {
      const y = Y(price);
      if (y == null) return;
      const yy = Math.round(y) + 0.5;
      g.strokeStyle = color; g.lineWidth = 1; g.setLineDash(dash || []);
      g.beginPath(); g.moveTo(Math.max(0, x0), yy); g.lineTo(Math.min(w, x1), yy); g.stroke(); g.setLineDash([]);
      if (label) { g.fillStyle = color; g.textAlign = "right"; g.fillText(label, Math.min(w, x1) - 4, yy - 7); }
    };
    const p = o.plan;
    // Yesterday's high / low / close and today's open, from the start of today.
    if (cfg.levels && p) {
      const x0 = T(p.dayStart);
      const xs = x0 == null ? 0 : x0;
      hl(p.pdh, xs, w, rgba(cfg.level, 0.9), [6, 4], `PDH ${fmt(p.pdh)}`);
      hl(p.pdl, xs, w, rgba(cfg.level, 0.9), [6, 4], `PDL ${fmt(p.pdl)}`);
      if (p.dayOpen != null) hl(p.dayOpen, xs, w, "rgba(160, 160, 170, 0.9)", [2, 3], `Mở ngày ${fmt(p.dayOpen)}`);
    }
    // H1 / H4 zones near price: boxes from where they formed.
    if (cfg.zones && o.zones) {
      const buy = o.zones.filter((z) => z.dir > 0).slice(0, cfg.zoneCount), sell = o.zones.filter((z) => z.dir < 0).slice(0, cfg.zoneCount);
      [...buy, ...sell].forEach((z) => {
        const x0 = T(z.from), y0 = Y(z.top), y1 = Y(z.bottom);
        if (y0 == null || y1 == null) return;
        const left = Math.max(0, x0 == null ? 0 : x0), c = z.dir > 0 ? cfg.zoneBuy : cfg.zoneSell;
        g.fillStyle = rgba(c, z.tf === "H4" ? 0.07 : 0.045); g.fillRect(left, Math.min(y0, y1), w - left, Math.max(1, Math.abs(y1 - y0)));
        g.strokeStyle = rgba(c, 0.35); g.setLineDash([4, 3]); g.strokeRect(left + 0.5, Math.min(y0, y1) + 0.5, w - left - 1, Math.max(1, Math.abs(y1 - y0))); g.setLineDash([]);
        g.fillStyle = c; g.textAlign = "left"; g.fillText(`${z.kind} ${z.tf}`, left + 4, Math.min(y0, y1) + 8);
      });
    }
    // Trendlines: through their touches, to the breakout (or on to now), the touches numbered.
    if (cfg.trend && o.trends) {
      o.trends.slice().reverse().forEach((l) => {
        const tEnd = l.breakAt != null ? l.breakBar + o.trendSec : null;
        const xa = T(l.t0), xb = tEnd != null ? T(tEnd) : w;
        if (xa == null && xb == null) return;
        const ya = Y(l.p0), yb = tEnd != null ? Y(l.price(tEnd)) : null;
        const c = l.breakAt == null ? cfg.trendColor : l.breakType === "fake" ? (l.dir < 0 ? cfg.bear : cfg.bull) : "#787b86";
        g.strokeStyle = c; g.lineWidth = l.breakAt == null ? 1.6 : 1;
        if (xa != null && ya != null) {
          g.beginPath(); g.moveTo(xa, ya);
          if (tEnd != null && xb != null && yb != null) g.lineTo(xb, yb);
          else {
            // On to the right edge: the time there from two points on screen.
            const tNow = o.lastTime || l.lastTouch, xn = T(tNow), yn = Y(l.price(tNow));
            if (xn != null && yn != null) { const k = (yn - ya) / Math.max(1, xn - xa); g.lineTo(w, ya + k * (w - xa)); }
          }
          g.stroke();
        }
        l.pts.forEach((pt, k) => {
          const x = T(pt.t), y = Y(pt.p);
          if (x == null || y == null) return;
          const yy = y + (l.dir < 0 ? -10 : 10);
          g.fillStyle = "rgba(21, 28, 42, 0.85)"; g.beginPath(); g.arc(x, yy, 6.5, 0, Math.PI * 2); g.fill();
          g.strokeStyle = c; g.lineWidth = 1; g.stroke();
          g.fillStyle = c; g.textAlign = "center"; g.fillText(String(k + 1), x, yy + 0.5);
        });
        if (l.breakAt != null) {
          const x = T(l.breakBar), y = Y(l.price(l.breakBar));
          if (x != null && y != null) pill(g, l.breakType === "fake" ? "BO giả" : l.breakType === "real" ? "BO thật" : "BO?", x + 4, y + (l.dir < 0 ? -16 : 16), rgba(c, 0.9));
        }
      });
    }
    // Signals: the trade as a box, the label with what it was and how it ended.
    if (cfg.signals && o.signals) {
      o.signals.slice(-Math.max(1, cfg.signalCount)).forEach((s) => {
        const x0 = X(s.at), x1 = s.res === "open" ? w : X(s.exitAt);
        const ye = Y(s.entry), ys = Y(s.stop), yt = Y(s.target);
        if (x0 == null || x1 == null || ye == null || ys == null || yt == null || x1 < 0) return;
        const left = Math.max(0, x0), width = Math.max(20, x1 - left);
        g.fillStyle = rgba(cfg.bull, 0.15); g.fillRect(left, Math.min(ye, yt), width, Math.abs(yt - ye));
        g.fillStyle = rgba(cfg.bear, 0.15); g.fillRect(left, Math.min(ye, ys), width, Math.abs(ys - ye));
        g.strokeStyle = s.dir > 0 ? cfg.bull : cfg.bear; g.lineWidth = 1.5;
        g.beginPath(); g.moveTo(left, Math.round(ye) + 0.5); g.lineTo(left + width, Math.round(ye) + 0.5); g.stroke();
        const xr = X(s.signal), yr = Y(s.dir > 0 ? s.stop : s.stop);
        if (xr != null && yr != null) {
          g.fillStyle = s.dir > 0 ? cfg.bull : cfg.bear; g.beginPath();
          if (s.dir > 0) { g.moveTo(xr, yr + 4); g.lineTo(xr - 5, yr + 12); g.lineTo(xr + 5, yr + 12); }
          else { g.moveTo(xr, yr - 4); g.lineTo(xr - 5, yr - 12); g.lineTo(xr + 5, yr - 12); }
          g.closePath(); g.fill();
        }
        const res = s.res === "open" ? "đang chạy" : `${s.r >= 0 ? "+" : ""}${s.r.toFixed(1)}R ${s.r > 0 ? "✓" : "✗"}`;
        pill(g, `${s.dir > 0 ? "MUA" : "BÁN"} · ${KIND[s.kind]} · ${s.bias} bias · ${res}`, left, (s.dir > 0 ? Math.max(ye, ys) : Math.min(ye, ys)) + (s.dir > 0 ? 22 : -22), s.res === "open" ? "rgba(41, 98, 255, 0.9)" : s.r > 0 ? rgba(cfg.bull, 0.9) : rgba(cfg.bear, 0.9));
      });
    }
    g.restore();
  }

  /** The plan in a few lines, bottom left, over the candles. */
  function drawPanel(g, o, cfg, w, h) {
    if (!o || !cfg.panel || !o.lines || !o.lines.length) return;
    g.save();
    g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif"; g.textBaseline = "middle";
    const lh = 17, pad = 8, maxW = Math.min(w - 20, 620);
    const fit = (t, max) => { if (g.measureText(t).width <= max) return t; let s = t; while (s.length > 10 && g.measureText(s + "…").width > max) s = s.slice(0, -1); return s + "…"; };
    const rows = o.lines.map((l) => ({ l, text: fit(l.text, maxW - pad * 2 - 10) }));
    const bw = Math.min(maxW, Math.max(...rows.map((r) => g.measureText(r.text).width)) + pad * 2 + 10), bh = rows.length * lh + pad * 2 - 4, bx = 10, by = h - bh - 44;
    g.fillStyle = "rgba(15, 20, 30, 0.94)"; g.beginPath(); g.roundRect(bx, by, bw, bh, 8); g.fill();
    rows.forEach((r, i) => {
      const yy = by + pad + i * lh + 6;
      g.fillStyle = r.l.dir > 0 ? cfg.bull : r.l.dir < 0 ? cfg.bear : "#c9d1dc";
      g.beginPath(); g.arc(bx + pad + 3, yy, 3, 0, Math.PI * 2); g.fill();
      g.fillStyle = "#e8ecf3"; g.textAlign = "left"; g.fillText(r.text, bx + pad + 12, yy + 0.5);
    });
    g.restore();
  }

  window.PLAN = { defaults, merge, compute, draw, drawPanel, dayPlan, trendlines, zonesOf, rejection, aggregate, KIND, pipSize };
})();
