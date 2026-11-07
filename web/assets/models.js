/* TTrades Model (from the IMC / TTrades documents), drawn on the web chart:
 *  - the higher-timeframe swing: candles 1-2-3-4 (candle 2 closure back into candle 1, or the candle 3
 *    conditional closure), the equilibrium of the candle 2 wick / candle 3 range that should hold, the
 *    previous candle high / low (PCH / PCL) and the bias they give (failure to displace, next candle model);
 *  - on the chart's own timeframe: CISD (a close through the open of the series of opposing candles that ran
 *    into a swept high / low) with standard deviation projections of the manipulation leg (-1, -2, -2.5, -4);
 *  - breaker blocks and the unicorn (a breaker overlapped by the fair value gap of the move that broke it);
 *  - the calendar rules: no trading on Monday, nor the day before a red USD news, nor through a news.
 * Pairs (chart timeframe → its higher timeframe) follow the model: 1m→15m, 3m→30m, 5m→1h, 15m→4h, 1h→1D, 4h→1W. */
(() => {
  "use strict";

  function defaults() {
    return {
      // "setup": each swing frozen as a setup with its own levels, trade and status; "full": the live story.
      view: "setup", setupCount: 4, setupSkips: true, setupDead: false,
      // The checklist: "score" = required factors + a minimum count; "filters" = the "Vào lệnh M1" switches.
      setupMode: "score", setupMust: "kz,profile,cal", setupMinScore: 6,
      htf: "auto", swing: true, eqLines: true, pcl: true, cisd: true, cisdPoiOnly: true, cisdCount: 3,
      projections: true, projLevels: "-1,-2,-2.5,-4", breakers: true, breakerCount: 3, unicorn: true, rules: true, panel: true,
      // M1 entries (the fractal model's 15m → 1m), shown on the 1-minute chart.
      entries: true, entryTarget: "1.5R", entrySpread: 0.3, entryBot: "ttrades", entryKillzones: true, entryNyPm: false, entryAsia: false, entrySkipMonday: false, entryOnePerSwing: true,
      entryStop: "leg", entryIdeal: false, entryDailyProfile: true, entryDailyBias: false, entryNews: false,
      entryDiscount: true, entryAlignH1: false, entryStrong: false, entryPartial: false, entryMode: "market",
      bull: "#089981", bear: "#f23645", eqColor: "#f2c14e", projColor: "#9c6bff", breakerColor: "#787b86", unicornColor: "#e91e63",
    };
  }

  function merge(saved) {
    const d = defaults();
    if (!saved || typeof saved !== "object") return d;
    Object.keys(d).forEach((k) => { if (saved[k] !== undefined && typeof saved[k] === typeof d[k]) d[k] = saved[k]; });
    return d;
  }

  const HTF_NAMES = { 300: "5m", 900: "15m", 1800: "30m", 3600: "H1", 14400: "H4", 86400: "D1", 604800: "W1" };

  /** The model's higher timeframe for a chart timeframe (seconds). */
  function pairOf(sec, choice) {
    if (choice && choice !== "auto") return +choice;
    if (sec < 60) return 300;
    if (sec <= 60) return 900;
    if (sec <= 180) return 1800;
    if (sec <= 300) return 3600;
    if (sec <= 900) return 14400;
    if (sec <= 3600) return 86400;
    return 604800;
  }

  /** Bucket start of `t` for a bar of `sec` (weeks from Monday 00:00 UTC, the broker's week). */
  function bucket(t, sec) {
    if (sec >= 604800) { const mon = 4 * 86400; return Math.floor((t - mon) / 604800) * 604800 + mon; }
    return Math.floor(t / sec) * sec;
  }

  /** Higher timeframe candles from the chart's bars, each with the chart index it starts at. */
  function aggregate(bars, sec, htf) {
    const out = [];
    bars.forEach((b, i) => {
      const t = bucket(b.time, htf), last = out[out.length - 1];
      if (last && last.time === t) {
        last.high = Math.max(last.high, b.high); last.low = Math.min(last.low, b.low); last.close = b.close; last.end = i;
      } else out.push({ time: t, open: b.open, high: b.high, low: b.low, close: b.close, start: i, end: i });
    });
    const lastBar = bars[bars.length - 1];
    out.forEach((c) => { c.done = true; });
    if (out.length && lastBar.time + sec < out[out.length - 1].time + htf) out[out.length - 1].done = false;
    return out;
  }

  const bodyTop = (b) => Math.max(b.open, b.close), bodyBot = (b) => Math.min(b.open, b.close);

  /** Pivot highs / lows with `len` bars on each side. */
  function pivots(bars, len) {
    const highs = [], lows = [];
    for (let i = len; i < bars.length - len; i++) {
      let hi = true, lo = true;
      for (let k = 1; k <= len; k++) {
        if (bars[i - k].high >= bars[i].high || bars[i + k].high > bars[i].high) hi = false;
        if (bars[i - k].low <= bars[i].low || bars[i + k].low < bars[i].low) lo = false;
      }
      if (hi) highs.push(i);
      if (lo) lows.push(i);
    }
    return { highs, lows };
  }

  /* ----- higher timeframe: candles 1-2-3-4 and the bias ----- */

  function htfStory(h, fmt) {
    const done = h.filter((c) => c.done), n = done.length;
    const out = { candles: h, swing: null, bias: null, pch: null, pcl: null };
    if (n >= 1) { out.pch = done[n - 1]; }
    // The newest swing formation among the last completed candles.
    for (let i = n - 1; i >= Math.max(1, n - 4); i--) {
      const c1 = done[i - 1], c2 = done[i], c3 = done[i + 1] || h[h.indexOf(c2) + 1], c4 = c3 ? h[h.indexOf(c3) + 1] : null;
      const tookLow = c2.low < c1.low, tookHigh = c2.high > c1.high;
      let dir = 0, kind = null;
      if (tookLow && c2.close > c1.low && !(tookHigh && c2.close < c1.high && c2.close < c2.open)) { dir = 1; kind = "c2"; }
      else if (tookHigh && c2.close < c1.high) { dir = -1; kind = "c2"; }
      else if (tookLow && c3 && c3.done && c3.close > c2.high) { dir = 1; kind = "c3"; }
      else if (tookHigh && c3 && c3.done && c3.close < c2.low) { dir = -1; kind = "c3"; }
      if (!dir) continue;
      // Candle 2's wick (or its range when the wick is small) is the level candle 3 should hold.
      const range = c2.high - c2.low || 1e-9;
      const wick = dir > 0 ? bodyBot(c2) - c2.low : c2.high - bodyTop(c2);
      const eq2 = wick >= range * 0.3 ? { price: dir > 0 ? c2.low + wick / 2 : c2.high - wick / 2, label: "EQ râu nến 2" }
        : { price: (c2.high + c2.low) / 2, label: "EQ nến 2" };
      const strong3 = c3 && c3.done && (dir > 0 ? c3.close > c2.high || (c3.close > c3.open && c3.close > (c3.high + c3.low) / 2 && c3.close > bodyTop(c2))
        : c3.close < c2.low || (c3.close < c3.open && c3.close < (c3.high + c3.low) / 2 && c3.close < bodyBot(c2)));
      const eq3 = strong3 ? { price: (c3.high + c3.low) / 2, label: "EQ nến 3" } : null;
      // Broken: a close back beyond candle 2's extreme.
      const after = h.slice(h.indexOf(c2) + 1);
      const broken = after.some((c) => (dir > 0 ? c.close < c2.low : c.close > c2.high));
      const target = dir > 0 ? c1.high : c1.low;
      let state;
      if (broken) state = `đã hỏng (đóng ${dir > 0 ? "dưới đáy" : "trên đỉnh"} nến 2)`;
      else if (kind === "c3" && (!c4 || !c4.done)) state = `nến 3 đóng mạnh → chờ nến 4 ${dir > 0 ? "TĂNG" : "GIẢM"}, giữ ${dir > 0 ? "trên" : "dưới"} ${fmt(eq3 ? eq3.price : (c3.high + c3.low) / 2)}`;
      else if (!c3 || !c3.done) state = `chờ nến 3 ${dir > 0 ? "TĂNG" : "GIẢM"}, giữ ${dir > 0 ? "trên" : "dưới"} ${eq2.label} ${fmt(eq2.price)}`;
      else if (strong3 && (!c4 || !c4.done)) state = `nến 3 đóng mạnh → chờ nến 4 tiếp diễn, giữ ${dir > 0 ? "trên" : "dưới"} EQ nến 3 ${fmt(eq3.price)}`;
      else if (!strong3) state = "nến 3 đóng yếu → chưa rõ, đứng ngoài";
      else state = "nến 4 đã chạy xong";
      out.swing = { dir, kind, c1, c2, c3: c3 || null, c4: c4 || null, eq2, eq3, broken, target, state };
      break;
    }
    // Previous candle high / low and the bias from the last two candles (MMXM next candle model).
    if (n >= 2) {
      const b = done[n - 2], c = done[n - 1];
      let dir = 0, why;
      if (c.close > b.high) { dir = 1; why = `nến trước đóng trên đỉnh nến trước nữa → hướng tới PCH ${fmt(c.high)}`; }
      else if (c.close < b.low) { dir = -1; why = `nến trước đóng dưới đáy nến trước nữa → hướng tới PCL ${fmt(c.low)}`; }
      else if (c.high > b.high && c.close < b.high) { dir = -1; why = `quét đỉnh nhưng không đóng qua (failure to displace) → hướng PCL ${fmt(c.low)}`; }
      else if (c.low < b.low && c.close > b.low) { dir = 1; why = `quét đáy nhưng không đóng qua (failure to displace) → hướng PCH ${fmt(c.high)}`; }
      else why = "nến trong (inside) → chờ thêm";
      out.bias = { dir, why };
      out.pch = c; out.pcl = c;
    }
    return out;
  }

  /* ----- chart timeframe: CISD at a point of interest, with projections ----- */

  function cisds(bars, levels, poiLevels, onlyPoi) {
    const piv = pivots(bars, 3);
    const out = [];
    const n = bars.length;
    let up = null, down = null; // the latest series of up-close / down-close candles
    for (let i = 0; i < n; i++) {
      const b = bars[i];
      if (b.close > b.open) {
        if (up && up.end === i - 1) { up.end = i; } else up = { start: i, end: i, level: b.open, used: false };
      } else if (b.close < b.open) {
        if (down && down.end === i - 1) { down.end = i; } else down = { start: i, end: i, level: b.open, used: false };
      }
      // Bearish: a close below the open of the up-close series that ran into the high.
      if (up && !up.used && i > up.end && b.close < up.level) {
        up.used = true;
        let hi = up.start;
        for (let k = up.start; k <= i; k++) if (bars[k].high > bars[hi].high) hi = k;
        let lo = up.start;
        for (let k = Math.max(0, up.start - 3); k <= hi; k++) if (bars[k].low < bars[lo].low) lo = k;
        const poi = sweptAbove(bars, piv.highs, hi, 60, i) || poiLevels.some((p) => bars[hi].high > p && Math.min(bars[up.start].low, bars[lo].low) < p);
        if (!onlyPoi || poi) out.push(projected(-1, up.level, up.start, i, bars[hi].high, bars[lo].low, hi, poi, levels));
      }
      if (down && !down.used && i > down.end && b.close > down.level) {
        down.used = true;
        let lo = down.start;
        for (let k = down.start; k <= i; k++) if (bars[k].low < bars[lo].low) lo = k;
        let hi = down.start;
        for (let k = Math.max(0, down.start - 3); k <= lo; k++) if (bars[k].high > bars[hi].high) hi = k;
        const poi = sweptBelow(bars, piv.lows, lo, 60, i) || poiLevels.some((p) => bars[lo].low < p && Math.max(bars[down.start].high, bars[hi].high) > p);
        if (!onlyPoi || poi) out.push(projected(1, down.level, down.start, i, bars[hi].high, bars[lo].low, lo, poi, levels));
      }
    }
    return out;
  }

  /** The extreme at `at` took a pivot high / low formed before it (within `look` bars). */
  /** First index in the sorted list `xs` whose value is ≥ v. */
  function lowerBound(xs, v) {
    let lo = 0, hi = xs.length;
    while (lo < hi) { const m = (lo + hi) >> 1; if (xs[m] < v) lo = m + 1; else hi = m; }
    return lo;
  }
  function sweptAbove(bars, highs, at, look, now) {
    for (let k = lowerBound(highs, at - look); k < highs.length && highs[k] < at - 1; k++) {
      const p = highs[k];
      if (p + 3 <= now && bars[at].high > bars[p].high) return true;
    }
    return false;
  }
  function sweptBelow(bars, lows, at, look, now) {
    for (let k = lowerBound(lows, at - look); k < lows.length && lows[k] < at - 1; k++) {
      const p = lows[k];
      if (p + 3 <= now && bars[at].low < bars[p].low) return true;
    }
    return false;
  }

  /** CISD with the standard deviations of the manipulation leg: bullish 1 = the low, 0 = the high before it;
   *  targets above at -1, -2, -2.5, -4 (bearish the other way round). */
  function projected(dir, level, from, at, hi, lo, extreme, poi, levels) {
    const leg = hi - lo;
    const proj = levels.map((k) => ({ k, price: dir > 0 ? hi + leg * Math.abs(k) : lo - leg * Math.abs(k) }));
    return { dir, level, from, at, hi, lo, extreme, poi, proj };
  }

  /* ----- breakers and the unicorn ----- */

  function breakers(bars, wantUnicorn) {
    const { highs, lows } = pivots(bars, 2);
    const out = [];
    const zone = (i) => {
      const a = bars[Math.max(0, i - 1)], b = bars[i];
      return { top: Math.max(bodyTop(a), bodyTop(b)), bottom: Math.min(bodyBot(a), bodyBot(b)) };
    };
    // Bullish: low L, high H, lower low (sweeps L), then a close above H → the zone at H.
    for (const h of highs) {
      const L = lows.filter((l) => l < h).pop();
      if (L == null || h - L > 30) continue;
      let swept = -1, broke = -1;
      for (let k = h + 1; k < Math.min(bars.length, h + 60); k++) {
        if (swept < 0) { if (bars[k].close > bars[h].high) break; if (bars[k].low < bars[L].low) swept = k; continue; }
        if (bars[k].close > bars[h].high) { broke = k; break; }
      }
      if (broke < 0) continue;
      out.push(finish(1, zone(h), h, swept, broke));
    }
    // Bearish: high H, low L, higher high (sweeps H), then a close below L → the zone at L.
    for (const l of lows) {
      const H = highs.filter((x) => x < l).pop();
      if (H == null || l - H > 30) continue;
      let swept = -1, broke = -1;
      for (let k = l + 1; k < Math.min(bars.length, l + 60); k++) {
        if (swept < 0) { if (bars[k].close < bars[l].low) break; if (bars[k].high > bars[H].high) swept = k; continue; }
        if (bars[k].close < bars[l].low) { broke = k; break; }
      }
      if (broke < 0) continue;
      out.push(finish(-1, zone(l), l, swept, broke));
    }

    function finish(dir, z, from, swept, broke) {
      // Ends at the first close back through it.
      let to = null;
      for (let k = broke + 1; k < bars.length; k++) if (dir > 0 ? bars[k].close < z.bottom : bars[k].close > z.top) { to = k; break; }
      // Unicorn: a fair value gap of the move that broke the level overlapping the breaker.
      let uni = null;
      if (wantUnicorn) {
        for (let j = swept + 2; j <= Math.min(bars.length - 1, broke + 1); j++) {
          const gapTop = dir > 0 ? bars[j].low : bars[j - 2].low, gapBot = dir > 0 ? bars[j - 2].high : bars[j].high;
          if (gapTop <= gapBot) continue;
          const top = Math.min(gapTop, z.top), bottom = Math.max(gapBot, z.bottom);
          if (top > bottom) { uni = { top, bottom, at: j - 1 }; break; }
        }
      }
      return { dir, top: z.top, bottom: z.bottom, from, swept, broke, to, unicorn: uni };
    }
    return out.sort((a, b) => a.broke - b.broke);
  }

  /* ----- the calendar rules ----- */

  const NY = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", weekday: "short", year: "numeric", month: "2-digit", day: "2-digit" });
  function nyDay(t) {
    const p = Object.fromEntries(NY.formatToParts(new Date(t * 1000)).map((x) => [x.type, x.value]));
    return { key: `${p.year}-${p.month}-${p.day}`, weekday: p.weekday };
  }

  function rules(lastTime, events) {
    const notes = [];
    const today = nyDay(lastTime);
    if (today.weekday === "Mon") notes.push("Thứ Hai: mô hình không giao dịch (ngày biên độ nhỏ, chưa có hồ sơ tuần)");
    const tomorrow = nyDay(lastTime + 86400 + (today.weekday === "Fri" ? 2 * 86400 : 0)).key;
    const red = (events || []).filter((e) => e.country === "USD" && e.impact === "High");
    const next = red.find((e) => nyDay(e.time).key === tomorrow);
    if (next) notes.push(`Ngày trước tin đỏ (${next.title}): tránh mở lệnh`);
    const soon = (events || []).filter((e) => e.country === "USD" && (e.impact === "High" || e.impact === "Medium") && e.time > lastTime && e.time - lastTime < 3 * 3600);
    if (soon.length) notes.push(`Sắp có tin ${soon[0].title}: không giữ lệnh qua tin`);
    return notes;
  }

  /* ----- M1 entries (TTrades fractal model: 15m swing → 1m CISD) and their backtest ----- */

  const NY_OFF = new Map();
  const NY_PARTS = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", weekday: "short" });
  /** New York hour (0-24, fractional) and weekday of a UTC time, cached per hour. */
  function nyClock(t) {
    const hk = Math.floor(t / 3600);
    let v = NY_OFF.get(hk);
    if (!v) {
      const p = Object.fromEntries(NY_PARTS.formatToParts(new Date(hk * 3600000)).map((x) => [x.type, x.value]));
      const local = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24) / 1000;
      v = { hour: +p.hour % 24, weekday: p.weekday, day: Math.floor(local / 86400) };
      NY_OFF.set(hk, v);
    }
    return { hour: v.hour + (t % 3600) / 3600, weekday: v.weekday, day: v.day };
  }

  function entryDefaults() {
    return { htf: 900, killzones: true, skipMonday: true, target: "2R", minRisk: 0.8, maxRisk: 15, spread: 0.3, maxHold: 240,
      maxPerSetup: 2, poiOnly: true, kz: [[2, 5], [7, 10]], stopMode: "leg", idealOnly: false,
      dailyProfile: false, dailyBias: false, newsWindows: false,
      targetR: 2, minTargetR: 1, entryMode: "market", limitBars: 15, partialFrac: 0, partialR: 1,
      htfAlign: false, discount: false, strongCisd: 0 };
  }

  /** The day's profile so far, as the model reads it (New York time): Asia = 20:00-24:00 the evening before,
   *  London = 02:00-05:00.
   *   - London reversal: London took one side of Asia and closed back inside → New York continues it;
   *   - London expansion: London broke one side and stayed out → stay out of New York;
   *   - consolidation / opposing run: London stayed inside Asia → New York may reverse (either way). */
  function dayProfiles(bars) {
    const days = new Map(); // NY day → { asiaHi, asiaLo, lonHi, lonLo, lonClose, lonEnd, sweptLow, sweptHigh }
    bars.forEach((b, i) => {
      const ck = nyClock(b.time);
      const key = ck.hour >= 20 ? ck.day + 1 : ck.day;
      let d = days.get(key);
      if (!d) { d = { asiaHi: -Infinity, asiaLo: Infinity, lonHi: -Infinity, lonLo: Infinity, lonClose: null, lonEnd: -1, firstSweep: null, sweepAt: {} }; days.set(key, d); }
      if (ck.hour >= 20) { d.asiaHi = Math.max(d.asiaHi, b.high); d.asiaLo = Math.min(d.asiaLo, b.low); }
      else if (ck.hour >= 2 && ck.hour < 5 && isFinite(d.asiaHi)) {
        d.lonHi = Math.max(d.lonHi, b.high); d.lonLo = Math.min(d.lonLo, b.low); d.lonClose = b.close; d.lonEnd = i;
        if (b.low < d.asiaLo && d.sweepAt.low == null) d.sweepAt.low = i;
        if (b.high > d.asiaHi && d.sweepAt.high == null) d.sweepAt.high = i;
      }
    });
    days.forEach((d) => {
      if (!isFinite(d.asiaHi) || d.lonClose == null) { d.kind = "none"; return; }
      const tookLow = d.lonLo < d.asiaLo, tookHigh = d.lonHi > d.asiaHi;
      if (tookLow && !tookHigh) d.kind = d.lonClose > d.asiaLo ? "londonReversalUp" : "londonExpansionDown";
      else if (tookHigh && !tookLow) d.kind = d.lonClose < d.asiaHi ? "londonReversalDown" : "londonExpansionUp";
      else if (tookHigh && tookLow) d.kind = "londonBoth";
      else d.kind = "consolidation";
    });
    return days;
  }

  /** May a trade of `dir` open at bar `i` (New York clock `ck`) by the day's profile? */
  function profileAllows(days, ck, i, dir) {
    const d = days.get(ck.hour >= 20 ? ck.day + 1 : ck.day);
    // Asia (20:00 to midnight New York): London has not traded yet, so the day's profile says nothing.
    if (ck.hour >= 20) return true;
    if (!d) return false;
    if (ck.hour >= 2 && ck.hour < 5) {
      // In London: only after London has taken the Asia side against the trade (the manipulation).
      const at = dir > 0 ? d.sweepAt.low : d.sweepAt.high;
      return at != null && at < i;
    }
    if (ck.hour >= 5) {
      if (d.kind === "londonReversalUp") return dir > 0;
      if (d.kind === "londonReversalDown") return dir < 0;
      if (d.kind === "londonExpansionUp" || d.kind === "londonExpansionDown" || d.kind === "londonBoth") return false;
      return d.kind === "consolidation";
    }
    return false;
  }

  /** The daily bias (previous day high / low, next candle model) for each chart bar: +1, -1 or 0. */
  function dailyBiasAt(bars) {
    const days = aggregate(bars, 60, 86400);
    const bias = new Array(bars.length).fill(0);
    for (let k = 2; k < days.length; k++) {
      const b = days[k - 2], c = days[k - 1];
      let dir = 0;
      if (c.close > b.high) dir = 1;
      else if (c.close < b.low) dir = -1;
      else if (c.high > b.high && c.close < b.high) dir = -1;
      else if (c.low < b.low && c.close > b.low) dir = 1;
      for (let i = days[k].start; i <= days[k].end; i++) bias[i] = dir;
    }
    return bias;
  }

  /** For each bar, the bias of the candle of `sec` before the one it is in: +1, -1 or 0. */
  function candleBiasAt(bars, sec) {
    const c = aggregate(bars, 60, sec);
    const out = new Array(bars.length).fill(0);
    for (let k = 2; k < c.length; k++) {
      const a = c[k - 2], b = c[k - 1];
      let dir = 0;
      if (b.close > a.high) dir = 1;
      else if (b.close < a.low) dir = -1;
      else if (b.high > a.high && b.close < a.high) dir = -1;
      else if (b.low < a.low && b.close > a.low) dir = 1;
      for (let i = c[k].start; i <= c[k].end; i++) out[i] = dir;
    }
    return out;
  }

  /** The average high-low range of the last `n` bars, at each bar. */
  function rangeAvg(bars, n) {
    const out = new Array(bars.length).fill(0);
    let sum = 0;
    bars.forEach((b, i) => {
      sum += b.high - b.low;
      if (i >= n) sum -= bars[i - n].high - bars[i - n].low;
      out[i] = sum / Math.min(i + 1, n);
    });
    return out;
  }

  /** New York 08:25-08:45 and 09:55-10:15: the usual release times of red USD news. */
  const NEWS_WINDOWS = [[8 + 25 / 60, 8.75], [9 + 55 / 60, 10.25]];

  /** The higher timeframe setups and, for each chart bar, the one it trades in (candle 3 / candle 4 window). */
  function setupsOf(bars, htfSec) {
    const h = aggregate(bars, 60, htfSec);
    const at = new Array(bars.length).fill(null);
    for (let j = 1; j < h.length; j++) {
      const c1 = h[j - 1], c2 = h[j], c3 = h[j + 1], c4 = h[j + 2];
      if (!c2.done || !c3) continue;
      const tookLow = c2.low < c1.low, tookHigh = c2.high > c1.high;
      let dir = 0, kind = null;
      if (tookLow && c2.close > c1.low && !(tookHigh && c2.close < c1.high && c2.close < c2.open)) { dir = 1; kind = "c2"; }
      else if (tookHigh && c2.close < c1.high) { dir = -1; kind = "c2"; }
      else if (tookLow && c3.done && c3.close > c2.high) { dir = 1; kind = "c3"; }
      else if (tookHigh && c3.done && c3.close < c2.low) { dir = -1; kind = "c3"; }
      if (!dir) continue;
      const range = c2.high - c2.low || 1e-9, wick = dir > 0 ? bodyBot(c2) - c2.low : c2.high - bodyTop(c2);
      const eq = kind === "c3" ? (c3.high + c3.low) / 2 : wick >= range * 0.3 ? (dir > 0 ? c2.low + wick / 2 : c2.high - wick / 2) : (c2.high + c2.low) / 2;
      const from = kind === "c3" ? (c4 ? c4.start : null) : c3.start;
      const to = kind === "c3" ? (c4 ? c4.end : null) : (c4 ? c4.end : c3.end);
      if (from == null) continue;
      // The ideal formation: candle 2 back inside candle 1 with a large wick.
      const ideal = kind === "c2" && wick >= range * 0.4;
      const setup = { id: j, dir, kind, eq, ideal, stop: dir > 0 ? c2.low : c2.high, target: dir > 0 ? c1.high : c1.low, from, to, c2, c1h: c1.high, c1l: c1.low };
      for (let i = from; i <= to; i++) at[i] = setup;
    }
    return at;
  }

  /** Entries on the chart's 1-minute bars: a CISD (at a point of interest) in the direction of the 15-minute
   *  swing, while candle 3 / candle 4 of that swing trade and price respects its equilibrium. Entry at the next
   *  bar's open, stop beyond the manipulation leg, target 2R (or the -2 / -4 projection). No look-ahead. */
  function entries(bars, opt) {
    opt = Object.assign(entryDefaults(), opt || {});
    const setupAt = setupsOf(bars, opt.htf);
    const days = opt.dailyProfile ? dayProfiles(bars) : null;
    const bias = opt.dailyBias ? dailyBiasAt(bars) : null;
    // Timeframe alignment: the 15m swing in the direction of the H1 candle's bias (the next candle model).
    const align = opt.htfAlign ? candleBiasAt(bars, 3600) : null;
    // Average 1m range (14 bars) for a "strong" CISD candle.
    const atr = opt.strongCisd > 0 ? rangeAvg(bars, 14) : null;
    const events = cisds(bars, [1, 2, 2.5, 4], [], opt.poiOnly);
    const out = [], used = new Map();
    // Why the CISDs were skipped: the backtest shows it, so a filter that blocks everything is plain to see.
    const skip = opt.tally || {};
    const no = (why) => { skip[why] = (skip[why] || 0) + 1; return true; };
    let busyUntil = -1;
    for (const e of events) {
      const i = e.at, s = setupAt[i];
      if (i + 1 >= bars.length) continue;
      if (!s && no("noSwing")) continue;
      if (s.dir !== e.dir && no("against")) continue;
      if (i <= busyUntil && no("busy")) continue;
      if (opt.idealOnly && !s.ideal && no("ideal")) continue;
      const b = bars[i];
      // The swing still holds: no close beyond candle 2's extreme, and the close respects the equilibrium.
      if ((s.dir > 0 ? b.close < s.eq : b.close > s.eq) && no("eq")) continue;
      let broken = false;
      for (let k = s.from; k <= i; k++) if (s.dir > 0 ? bars[k].close < s.stop : bars[k].close > s.stop) { broken = true; break; }
      if (broken && no("broken")) continue;
      const ck = nyClock(bars[i + 1].time);
      if (opt.skipMonday && ck.weekday === "Mon" && no("monday")) continue;
      if (opt.killzones && !opt.kz.some(([a, z]) => ck.hour >= a && ck.hour < z) && no("killzone")) continue;
      if (days && !profileAllows(days, ck, i, s.dir) && no("profile")) continue;
      if (bias && bias[i] !== s.dir && no("bias")) continue;
      if (align && align[i] !== s.dir && no("h1")) continue;
      // Buy in discount / sell in premium of candle 1 + candle 2's range (the swing's dealing range).
      if (opt.discount) {
        const hi = Math.max(s.c1h, s.c2.high), lo = Math.min(s.c1l, s.c2.low), mid = (hi + lo) / 2;
        if ((s.dir > 0 ? b.close > mid : b.close < mid) && no("discount")) continue;
      }
      if (atr && Math.abs(b.close - b.open) < atr[i] * opt.strongCisd && no("strong")) continue;
      if (opt.newsWindows && NEWS_WINDOWS.some(([a, z]) => ck.hour >= a && ck.hour < z) && no("news")) continue;
      if ((used.get(s.id) || 0) >= opt.maxPerSetup && no("perSwing")) continue;
      // Stop beyond the 1-minute manipulation leg, or (the model's rule) beyond the higher timeframe candle 2.
      const stop = opt.stopMode === "c2" ? s.stop : s.dir > 0 ? e.lo : e.hi;
      // Entry: market at the next bar's open, or (the model's other way) a limit back at the CISD level, the
      // opposing candle's open, waiting `limitBars` bars.
      let entry = bars[i + 1].open, start = i + 1;
      if (opt.entryMode === "limit") {
        entry = e.level; start = -1;
        for (let k = i + 1; k < bars.length && k <= i + opt.limitBars; k++) {
          const x = bars[k];
          if (s.dir > 0 ? x.low <= stop : x.high >= stop) break; // the stop went first: no trade
          if (s.dir > 0 ? x.low <= entry : x.high >= entry) { start = k; break; }
        }
        if (start < 0 && no("unfilled")) continue;
      }
      const risk = Math.abs(entry - stop);
      if (((s.dir > 0 ? entry <= stop : entry >= stop) || risk < opt.minRisk || risk > opt.maxRisk) && no("risk")) continue;
      let target = entry + s.dir * risk * (opt.targetR || 2);
      // Targets on the chart: a standard deviation of the 1m leg, or the swing's own target (candle 1's other end).
      const stdK = { std1: 1, std2: 2, std25: 2.5, std4: 4 }[opt.target];
      if (stdK || opt.target === "c1") {
        const p = stdK ? e.proj.find((x) => Math.abs(x.k) === stdK) : null;
        target = stdK ? (p ? p.price : target) : s.target;
        if ((target - entry) * s.dir < risk * opt.minTargetR && no("target")) continue; // too little room to the target
      }
      // Partial: take `partialFrac` at `partialR` and move the stop to the entry (break-even).
      const partialAt = opt.partialFrac > 0 ? entry + s.dir * risk * opt.partialR : null;
      let banked = 0, left = 1, sl = stop;
      // Walk forward: the stop first when both are inside one bar.
      let exit = null, exitAt = null, why = "time";
      for (let k = start; k < bars.length && k <= start + opt.maxHold; k++) {
        const x = bars[k];
        // On the entry bar of a limit only what comes after the fill counts: its stop is still checked.
        if (s.dir > 0 ? x.low <= sl : x.high >= sl) { exit = sl; exitAt = k; why = left < 1 ? "breakeven" : "stop"; break; }
        if (partialAt != null && left === 1 && k > start - (opt.entryMode === "limit" ? 0 : 1) && (s.dir > 0 ? x.high >= partialAt : x.low <= partialAt)) {
          banked = opt.partialFrac * opt.partialR; left = 1 - opt.partialFrac; sl = entry;
          if (s.dir > 0 ? x.high >= target : x.low <= target) { exit = target; exitAt = k; why = "target"; break; }
          continue;
        }
        if (s.dir > 0 ? x.high >= target : x.low <= target) { exit = target; exitAt = k; why = "target"; break; }
      }
      if (exit == null) { exitAt = Math.min(bars.length - 1, start + opt.maxHold); exit = bars[exitAt].close; if (exitAt === bars.length - 1) why = "open"; }
      const r = banked + left * ((exit - entry) * s.dir) / risk - opt.spread / risk;
      const h = ck.hour, session = h >= 20 ? "asia" : h >= 2 && h < 5 ? "london" : h >= 7 && h < 10 ? "ny" : h >= 13.5 && h < 16 ? "pm" : "other";
      out.push({ dir: s.dir, at: start, signalAt: i, time: bars[start].time, entry, stop, target, risk, exit, exitAt, exitTime: bars[exitAt].time, why, r, kind: s.kind, partial: banked > 0, session });
      used.set(s.id, (used.get(s.id) || 0) + 1);
      busyUntil = exitAt;
    }
    return out;
  }

  /* ----- ICT liquidity model (2022 model / Silver Bullet style) ----- */

  /** Entries after a liquidity sweep: price trades through a pool (Asia high / low, previous day high / low,
   *  London high / low, 1h or 15m swing points), then within `sweepWin` bars closes through the last 1m swing
   *  on the other side (the market structure shift) with a fair value gap in the move. Entry at the next bar's
   *  open, stop beyond the sweep's extreme, target `targetR`. Only bars up to the signal are read. */
  function liquidityEntries(bars, opt) {
    const o = Object.assign({ pools: { asia: true, pd: true, london: true, h1: true, h15: false }, windows: [[2, 5], [7, 11], [13.5, 16]],
      targetR: 1, minRisk: 0.8, maxRisk: 10, spread: 0.3, maxHold: 240, sweepWin: 30, mssLook: 20 }, opt || {});
    const n = bars.length, out = [];
    // 15m / 1h swing points, live once the candles after them have closed.
    const swings = [];
    for (const [sec, kind] of [[900, "h15"], [3600, "h1"]]) {
      if (!o.pools[kind]) continue;
      const h = aggregate(bars, 60, sec);
      for (let k = 2; k + 2 < h.length; k++) {
        const hi = h[k - 1].high < h[k].high && h[k - 2].high < h[k].high && h[k + 1].high <= h[k].high && h[k + 2].high <= h[k].high;
        const lo = h[k - 1].low > h[k].low && h[k - 2].low > h[k].low && h[k + 1].low >= h[k].low && h[k + 2].low >= h[k].low;
        const born = h[k + 2].end + 1;
        if (hi) swings.push({ price: h[k].high, side: 1, kind, born });
        if (lo) swings.push({ price: h[k].low, side: -1, kind, born });
      }
    }
    swings.sort((a, b) => a.born - b.born);
    let sp = 0, key = null, day = null, prev = null, busy = -1;
    const pools = [], swingHi = [], swingLo = [], sweep = { 1: null, "-1": null };
    const add = (price, side, kind, i) => { if (isFinite(price)) pools.push({ price, side, kind, born: i }); };
    for (let i = 0; i < n; i++) {
      const b = bars[i], ck = nyClock(b.time);
      // The trading day starts at 18:00 New York.
      const k = ck.hour >= 18 ? ck.day + 1 : ck.day;
      if (k !== key) {
        prev = day; key = k;
        day = { hi: -Infinity, lo: Infinity, asiaHi: -Infinity, asiaLo: Infinity, lonHi: -Infinity, lonLo: Infinity, asiaDone: false, lonDone: false };
        if (prev && o.pools.pd) { add(prev.hi, 1, "pd", i); add(prev.lo, -1, "pd", i); }
      }
      if (ck.hour < 18 && !day.asiaDone && isFinite(day.asiaHi)) { day.asiaDone = true; if (o.pools.asia) { add(day.asiaHi, 1, "asia", i); add(day.asiaLo, -1, "asia", i); } }
      if (ck.hour >= 5 && ck.hour < 18 && !day.lonDone && isFinite(day.lonHi)) { day.lonDone = true; if (o.pools.london) { add(day.lonHi, 1, "london", i); add(day.lonLo, -1, "london", i); } }
      if (ck.hour >= 20) { day.asiaHi = Math.max(day.asiaHi, b.high); day.asiaLo = Math.min(day.asiaLo, b.low); }
      if (ck.hour >= 2 && ck.hour < 5) { day.lonHi = Math.max(day.lonHi, b.high); day.lonLo = Math.min(day.lonLo, b.low); }
      day.hi = Math.max(day.hi, b.high); day.lo = Math.min(day.lo, b.low);
      while (sp < swings.length && swings[sp].born <= i) { const w = swings[sp++]; pools.push({ price: w.price, side: w.side, kind: w.kind, born: i - 1 }); }
      // 1m swing points (two bars each side) for the structure shift.
      const q = i - 2;
      if (q >= 2) {
        if (bars[q - 1].high < bars[q].high && bars[q - 2].high < bars[q].high && bars[q + 1].high <= bars[q].high && bars[q + 2].high <= bars[q].high) swingHi.push(q);
        if (bars[q - 1].low > bars[q].low && bars[q - 2].low > bars[q].low && bars[q + 1].low >= bars[q].low && bars[q + 2].low >= bars[q].low) swingLo.push(q);
      }
      // Sweeps: a high pool taken → look for a sell; a low pool taken → a buy.
      for (const p of pools) {
        if (p.dead || p.born >= i) continue;
        if (p.side > 0 && b.high > p.price) { p.dead = true; const s = sweep[-1]; if (!s || b.high > s.ext || i - s.at > o.sweepWin) sweep[-1] = { ext: b.high, extAt: i, at: i, kind: p.kind }; }
        if (p.side < 0 && b.low < p.price) { p.dead = true; const s = sweep[1]; if (!s || b.low < s.ext || i - s.at > o.sweepWin) sweep[1] = { ext: b.low, extAt: i, at: i, kind: p.kind }; }
      }
      for (const d of [1, -1]) {
        const s = sweep[d];
        if (!s) continue;
        if (i - s.extAt > o.sweepWin) { sweep[d] = null; continue; }
        if (d < 0 && b.high > s.ext) { s.ext = b.high; s.extAt = i; }
        if (d > 0 && b.low < s.ext) { s.ext = b.low; s.extAt = i; }
      }
      if (i % 1440 === 0) { const keep = pools.filter((p) => !p.dead && i - p.born < 2880); pools.length = 0; pools.push(...keep); }
      // The structure shift: a close through the last 1m swing before the sweep's extreme.
      for (const d of [1, -1]) {
        const s = sweep[d];
        if (!s || s.done || i <= s.extAt) continue;
        const list = d > 0 ? swingHi : swingLo;
        let ref = null;
        for (let x = list.length - 1; x >= 0; x--) { if (list[x] >= s.extAt) continue; if (s.extAt - list[x] <= o.mssLook) ref = list[x]; break; }
        if (ref == null) continue;
        if (!(d > 0 ? b.close > bars[ref].high : b.close < bars[ref].low)) continue;
        s.done = true;
        // Displacement: a fair value gap in the move away from the extreme.
        let fvg = false;
        for (let x = i; x >= s.extAt + 2 && !fvg; x--) fvg = d > 0 ? bars[x].low > bars[x - 2].high : bars[x].high < bars[x - 2].low;
        if (!fvg || i + 1 >= n || i <= busy) continue;
        const ckn = nyClock(bars[i + 1].time);
        if (!o.windows.some(([a, z]) => ckn.hour >= a && ckn.hour < z)) continue;
        const entry = bars[i + 1].open, stop = s.ext, risk = (entry - stop) * d;
        if (risk < o.minRisk || risk > o.maxRisk) continue;
        const target = entry + d * risk * o.targetR;
        let exit = null, exitAt = null, why = "time";
        for (let x = i + 1; x < n && x <= i + 1 + o.maxHold; x++) {
          const c = bars[x];
          if (d > 0 ? c.low <= stop : c.high >= stop) { exit = stop; exitAt = x; why = "stop"; break; }
          if (d > 0 ? c.high >= target : c.low <= target) { exit = target; exitAt = x; why = "target"; break; }
        }
        if (exit == null) { exitAt = Math.min(n - 1, i + 1 + o.maxHold); exit = bars[exitAt].close; if (exitAt === n - 1) why = "open"; }
        const r = ((exit - entry) * d) / risk - o.spread / risk;
        const h = ckn.hour, session = h >= 20 ? "asia" : h >= 2 && h < 5 ? "london" : h >= 7 && h < 11 ? "ny" : h >= 13.5 && h < 16 ? "pm" : "other";
        out.push({ dir: d, at: i + 1, signalAt: i, time: bars[i + 1].time, entry, stop, target, risk, exit, exitAt, exitTime: bars[exitAt].time, why, r, kind: s.kind, session, dayKey: key });
        busy = exitAt;
      }
    }
    return out;
  }

  /** The daily bot: the TTrades M1 entries first, then the liquidity model's setups, one trade at a time.
   *  Tested on gold 1m (April to November 2026, MT5-like gaps, 0.3 spread) at about 58% wins in both halves,
   *  with a trade on about nine days in ten:
   *   A  TTrades M1 (the indicator's own settings),
   *   B  sweep of Asia / London / previous day / 1h liquidity + MSS in the killzones, target 1R,
   *   C  sweep of any of those or a 15m swing + MSS, New York 7–11h, target 0.8R,
   *   D  as C in the New York afternoon (13:30–16h), only on a day without a trade yet. */
  const BOT_MODELS = { A: "TTrades M1", B: "Quét thanh khoản phiên / H1", C: "Quét đỉnh đáy 15m · NY sáng", D: "Quét 15m · NY chiều (dự phòng)" };
  function dailyBot(bars, opt, spread) {
    const sp = spread != null ? spread : opt.spread;
    const all = [
      entries(bars, opt).map((t) => Object.assign(t, { model: "A" })),
      liquidityEntries(bars, { spread: sp }).map((t) => Object.assign(t, { model: "B" })),
      liquidityEntries(bars, { spread: sp, pools: { asia: true, pd: true, london: true, h1: true, h15: true }, windows: [[7, 11]], targetR: 0.8 }).map((t) => Object.assign(t, { model: "C" })),
      liquidityEntries(bars, { spread: sp, pools: { asia: true, pd: true, london: true, h1: true, h15: true }, windows: [[13.5, 16]], targetR: 0.8 }).map((t) => Object.assign(t, { model: "D" })),
    ].flat().sort((a, b) => a.at - b.at || a.model.localeCompare(b.model));
    const out = [], perDay = new Map();
    let busy = -1;
    for (const t of all) {
      if (t.at <= busy) continue;
      if (t.dayKey == null) { const c = nyClock(t.time); t.dayKey = c.hour >= 18 ? c.day + 1 : c.day; }
      const n = perDay.get(t.dayKey) || 0;
      if (t.model === "D" && n > 0) continue;
      out.push(t); busy = t.exitAt; perDay.set(t.dayKey, n + 1);
    }
    return out;
  }

  /** The entries of the chosen bot. */
  function botEntries(bars, cfg, extra) {
    const opt = Object.assign(entryOptions(cfg), extra || {});
    return cfg.entryBot === "daily" ? dailyBot(bars, opt) : entries(bars, opt).map((t) => Object.assign(t, { model: "A" }));
  }

  /* ----- fixed setups ----- */

  /** Every higher timeframe swing as a fixed setup. Its levels are taken when candle 2 closes back inside candle 1
   *  (or candle 3 closes through candle 2) and never move afterwards. Inside its window (candles 3 and 4, or
   *  candle 4) the first CISD in its direction that passes the rules is the trade: entry at the next bar's open,
   *  stop beyond the CISD leg (or candle 2), target from the settings. Each setup ends in one status:
   *  wait (window open), signal (CISD on the last bar: entry at the next open), open, win, loss, flat (closed on
   *  time), broken (a close beyond candle 2 first), expired (no valid CISD in the window), skipped (not ideal).
   *  Only the bars up to each moment are read, so a setup on the chart is what it was at that time. */
  function setupTimeline(bars, sec, htfSec, cfg) {
    const n = bars.length;
    if (htfSec <= sec || n < 20) return [];
    const h = aggregate(bars, sec, htfSec), last = bars[n - 1];
    const intraday = sec <= 300;
    const opt = Object.assign(entryDefaults(), entryOptions(cfg));
    const events = cisds(bars, [1, 2, 2.5, 4], [], cfg.cisdPoiOnly !== false);
    const days = intraday && opt.dailyProfile ? dayProfiles(bars) : null;
    const bias = intraday && opt.dailyBias ? dailyBiasAt(bars) : null;
    const align = intraday && opt.htfAlign ? candleBiasAt(bars, 3600) : null;
    const atr = opt.strongCisd > 0 ? rangeAvg(bars, 14) : null;
    // The checklist from the documents: every factor for each CISD, a trade once the required ones hold and the
    // score reaches the minimum. (The arrays are for all bars; each one reads only the past.)
    const dayAll = intraday ? days || dayProfiles(bars) : null;
    const biasAll = intraday ? bias || dailyBiasAt(bars) : null;
    const alignAll = intraday ? align || candleBiasAt(bars, 3600) : null;
    const atrAll = atr || rangeAvg(bars, 14);
    const bks = breakers(bars, true);
    const must = new Set(String(cfg.setupMust || "").split(",").filter(Boolean));
    const minScore = cfg.setupMode === "score" ? Math.max(0, +cfg.setupMinScore || 0) : 0;
    const poiAt = (e, dir, i) => {
      const x = dir > 0 ? e.lo : e.hi, tol = atrAll[i] * 0.5;
      return bks.some((k) => k.dir === dir && k.broke < i && (k.to == null || k.to > i) && x >= k.bottom - tol && x <= k.top + tol);
    };
    function checklist(su, e, b, ck, entry, risk, waiting) {
      const d = su.dir, i = Math.min(e.at, n - 1), h = ck.hour;
      const list = [
        { k: "kz", short: "ngoài killzone", label: "Killzone: London 2–5h / NY 7–10h (giờ New York)", ok: !intraday || opt.kz.some(([a, z]) => h >= a && h < z) },
        { k: "profile", short: "hồ sơ ngày", label: "Hồ sơ ngày: London / NY đảo chiều, không phải London phá hẳn", ok: !intraday || profileAllows(dayAll, ck, i, d) },
        { k: "zone", short: d > 0 ? "chưa ở discount" : "chưa ở premium", label: d > 0 ? "Mua ở discount của nến 1 + 2" : "Bán ở premium của nến 1 + 2", ok: d > 0 ? b.close <= su.mid : b.close >= su.mid },
        { k: "dbias", short: "ngược bias ngày", label: "Bias ngày cùng chiều (PDH / PDL, failure to displace)", ok: !intraday || biasAll[i] === d },
        { k: "h1", short: "ngược nến H1", label: "Nến H1 trước cùng chiều (next candle model)", ok: !intraday || alignAll[i] === d },
        { k: "ideal", short: "không ideal", label: "Ideal formation: râu nến 2 dài (≥ 40%)", ok: su.ideal },
        { k: "poi", short: "không tại breaker", label: "Chân CISD tại breaker / unicorn", ok: waiting ? false : poiAt(e, d, i), later: waiting },
        { k: "cal", short: "Thứ Hai / giờ tin", label: "Không Thứ Hai, không trong giờ ra tin", ok: ck.weekday !== "Mon" && !NEWS_WINDOWS.some(([a, z]) => h >= a && h < z) },
        { k: "room", short: "không đủ 2R", label: "Còn ≥ 2R tới mục tiêu nến 1", ok: risk > 0 && (su.target - entry) * d >= 2 * risk, later: waiting },
        { k: "strong", short: "CISD yếu", label: "Nến CISD mạnh (thân ≥ biên độ trung bình)", ok: waiting ? false : Math.abs(b.close - b.open) >= atrAll[i], later: waiting },
      ];
      list.forEach((x) => { x.must = cfg.setupMode === "score" ? must.has(x.k) : legacyMust(x.k); });
      return list;
    }
    // The old switches (setupMode "filters"): the ones turned on are required.
    const legacyMust = (k) => (k === "kz" && intraday && opt.killzones) || (k === "profile" && !!days) || (k === "zone" && opt.discount)
      || (k === "dbias" && !!bias) || (k === "h1" && !!align) || (k === "ideal" && opt.idealOnly) || (k === "strong" && !!atr)
      || (k === "cal" && intraday && (opt.skipMonday || opt.newsWindows));
    const scoreOf = (list) => list.filter((x) => x.ok).length;
    const passes = (list) => list.every((x) => !x.must || x.ok) && scoreOf(list) >= minScore;
    const missing = (list) => { const m = list.filter((x) => x.must && !x.ok); return m.length ? m.map((x) => x.short).join(", ") : `${scoreOf(list)}/${list.length} điểm, cần ${minScore}`; };
    // Index of a time on this chart, past the last bar too (for a window that is still open).
    const idxOf = (t) => {
      if (t > last.time) return n - 1 + (t - last.time) / sec;
      let lo = 0, hi = n - 1;
      while (lo < hi) { const m = (lo + hi) >> 1; if (bars[m].time < t) lo = m + 1; else hi = m; }
      return lo;
    };
    const out = [];
    let num = 0;
    for (let j = 1; j < h.length; j++) {
      const c1 = h[j - 1], c2 = h[j], c3 = h[j + 1] || null;
      if (!c2.done) continue;
      const tookLow = c2.low < c1.low, tookHigh = c2.high > c1.high;
      let dir = 0, kind = null;
      if (tookLow && c2.close > c1.low && !(tookHigh && c2.close < c1.high && c2.close < c2.open)) { dir = 1; kind = "c2"; }
      else if (tookHigh && c2.close < c1.high) { dir = -1; kind = "c2"; }
      else if (tookLow && c3 && c3.done && c3.close > c2.high) { dir = 1; kind = "c3"; }
      else if (tookHigh && c3 && c3.done && c3.close < c2.low) { dir = -1; kind = "c3"; }
      if (!dir) continue;
      const range = c2.high - c2.low || 1e-9, wick = dir > 0 ? bodyBot(c2) - c2.low : c2.high - bodyTop(c2);
      const eq = kind === "c3" ? { price: (c3.high + c3.low) / 2, label: "EQ nến 3" }
        : wick >= range * 0.3 ? { price: dir > 0 ? c2.low + wick / 2 : c2.high - wick / 2, label: "EQ râu nến 2" } : { price: (c2.high + c2.low) / 2, label: "EQ nến 2" };
      const formedAt = kind === "c3" ? c3.end : c2.end;
      const endTime = kind === "c3" ? c3.time + 2 * htfSec : c2.time + 3 * htfSec;
      const from = formedAt + 1, toF = idxOf(endTime) - (endTime > last.time ? 0 : 1);
      const to = Math.min(n - 1, Math.floor(toF));
      const su = {
        n: ++num, id: c2.time, dir, kind, ideal: kind === "c2" && wick >= range * 0.4, htfSec,
        c1: { start: c1.start, end: c1.end, high: c1.high, low: c1.low }, c2: { start: c2.start, end: c2.end, high: c2.high, low: c2.low },
        formedAt, formedTime: bars[formedAt].time, from, endTime, endIdx: idxOf(endTime), active: last.time + sec < endTime,
        eq: eq.price, eqLabel: eq.label, invalid: dir > 0 ? c2.low : c2.high, swept: dir > 0 ? c1.low : c1.high, target: dir > 0 ? c1.high : c1.low,
        status: "wait", trade: null, skips: [], brokenAt: null,
      };
      out.push(su);
      for (let k = from; k <= to; k++) if (dir > 0 ? bars[k].close < su.invalid : bars[k].close > su.invalid) { su.brokenAt = k; break; }
      const hi = Math.max(c1.high, c2.high), lo = Math.min(c1.low, c2.low), mid = (hi + lo) / 2;
      su.mid = mid;
      for (const e of events) {
        const i = e.at;
        if (e.dir !== dir || i < from) continue;
        if (i > to || (su.brokenAt != null && su.brokenAt <= i)) break;
        const b = bars[i];
        const skip = (why, list) => { su.skips.push({ at: i, why, level: e.level, list }); };
        // The model itself: the CISD respects the equilibrium of the swing.
        if (dir > 0 ? b.close < su.eq : b.close > su.eq) { skip(`đóng ${dir > 0 ? "dưới" : "trên"} ${eq.label}`); continue; }
        const stop = cfg.entryStop === "c2" ? su.invalid : dir > 0 ? e.lo : e.hi;
        if (i + 1 >= n) {
          // The CISD closed on the last bar: the checklist with the close as the entry, the trade at the next open.
          const list = checklist(su, e, b, nyClock(last.time + sec), b.close, Math.abs(b.close - stop));
          su.list = list; su.score = scoreOf(list);
          if (passes(list)) { su.status = "signal"; su.trade = { cisd: { level: e.level, from: e.from, at: i }, at: n, stop }; }
          else skip(missing(list), list);
          break;
        }
        const ck = nyClock(bars[i + 1].time);
        const entry = bars[i + 1].open, risk = (entry - stop) * dir;
        if (risk <= 0 || (intraday && (risk < opt.minRisk || risk > opt.maxRisk))) { skip(risk <= 0 ? "giá đã vượt SL" : risk < opt.minRisk ? "SL quá gần" : "SL quá xa"); continue; }
        let target = entry + dir * risk * (opt.targetR || 2);
        const stdK = { std1: 1, std2: 2, std25: 2.5, std4: 4 }[opt.target];
        if (stdK) { const p = e.proj.find((x) => Math.abs(x.k) === stdK); if (p) target = p.price; }
        if (opt.target === "c1") target = su.target;
        if ((target - entry) * dir < risk * (stdK || opt.target === "c1" ? 1 : 0)) { skip("mục tiêu dưới 1R"); continue; }
        const list = checklist(su, e, b, ck, entry, risk);
        su.list = list; su.score = scoreOf(list);
        const ok = passes(list);
        if (!ok && !cfg._candidates) { skip(missing(list), list); continue; }
        let exit = null, exitAt = null, why = "time";
        for (let k = i + 1; k < n && k <= i + 1 + opt.maxHold; k++) {
          const x = bars[k];
          if (dir > 0 ? x.low <= stop : x.high >= stop) { exit = stop; exitAt = k; why = "stop"; break; }
          if (dir > 0 ? x.high >= target : x.low <= target) { exit = target; exitAt = k; why = "target"; break; }
        }
        if (exit == null) { exitAt = Math.min(n - 1, i + 1 + opt.maxHold); exit = bars[exitAt].close; if (exitAt === n - 1) why = "open"; }
        const r = ((exit - entry) * dir) / risk - opt.spread / risk;
        if (cfg._candidates) cfg._candidates.push({ setup: su.n, at: i, time: b.time, list: list.map((x) => x.ok), r, why });
        if (!ok) { skip(missing(list), list); continue; }
        su.trade = { cisd: { level: e.level, from: e.from, at: i }, at: i + 1, time: bars[i + 1].time, entry, stop, target, risk, exit, exitAt, exitTime: bars[exitAt].time, why, r };
        su.status = why === "open" ? "open" : why === "target" ? "win" : why === "stop" ? (r > 0 ? "win" : "loss") : r > 0 ? "win" : "flat";
        break;
      }
      if (!su.trade) su.status = su.brokenAt != null ? "broken" : su.active ? "wait" : "expired";
      // Still waiting: may a trade be taken right now? (The time, the day's profile, where price is.)
      if (su.status === "wait") {
        // What a CISD now would have: the checklist at the last close (the CISD and its leg not known yet).
        const e = { lo: dir > 0 ? Math.min(c2.low, last.low) : last.low, hi: dir < 0 ? Math.max(c2.high, last.high) : last.high, at: n - 1 };
        const list = checklist(su, e, last, nyClock(last.time + sec), last.close, Math.abs(last.close - su.invalid), true);
        su.list = list; su.score = scoreOf(list);
        const need = list.filter((x) => x.must && !x.ok && !x.later);
        if (need.length) su.blocked = need.map((x) => x.short).join(", ");
      }
    }
    return out;
  }

  const CHECK_NAMES = { kz: "Killzone", profile: "Hồ sơ ngày", zone: "Vùng", dbias: "Bias ngày", h1: "Nến H1", ideal: "Ideal", poi: "Breaker", cal: "Lịch", room: "≥ 2R", strong: "CISD mạnh" };
  const CHECK_LABELS = {
    kz: "Killzone: London 2–5h / NY 7–10h (giờ New York)", profile: "Hồ sơ ngày: London / NY đảo chiều (không phải London phá hẳn)",
    zone: "Mua ở discount / bán ở premium của nến 1 + 2", dbias: "Bias ngày cùng chiều (PDH / PDL, failure to displace)",
    h1: "Nến H1 trước cùng chiều (next candle model)", ideal: "Ideal formation: râu nến 2 dài (≥ 40%)", poi: "Chân CISD tại breaker / unicorn",
    cal: "Không Thứ Hai, không trong giờ ra tin", room: "Còn ≥ 2R tới mục tiêu nến 1", strong: "Nến CISD mạnh (thân ≥ biên độ trung bình)",
  };
  const SETUP_STATUS = { wait: "chờ CISD", signal: "CISD vừa xác nhận", open: "đang vào lệnh", win: "thắng", loss: "thua", flat: "đóng hoà", broken: "huỷ", expired: "hết giờ", skipped: "bỏ qua" };

  /** The entry options from the indicator's settings. */
  function entryOptions(cfg) {
    const rTarget = /^[\d.]+R$/.test(String(cfg.entryTarget)) ? parseFloat(cfg.entryTarget) : null;
    return { target: rTarget ? "R" : cfg.entryTarget, targetR: rTarget || 2, spread: +cfg.entrySpread || 0,
      discount: cfg.entryDiscount, htfAlign: cfg.entryAlignH1, strongCisd: cfg.entryStrong ? 1 : 0,
      partialFrac: cfg.entryPartial ? 0.5 : 0, partialR: 1, entryMode: cfg.entryMode, killzones: cfg.entryKillzones, skipMonday: cfg.entrySkipMonday,
      kz: [[2, 5], [7, 10]].concat(cfg.entryNyPm ? [[13.5, 16]] : [], cfg.entryAsia ? [[20, 24]] : []),
      maxPerSetup: cfg.entryOnePerSwing ? 1 : 2, stopMode: cfg.entryStop, idealOnly: cfg.entryIdeal, maxRisk: cfg.entryStop === "c2" ? 40 : 15,
      dailyProfile: cfg.entryDailyProfile, dailyBias: cfg.entryDailyBias, newsWindows: cfg.entryNews };
  }

  /** What each skip reason of `entries` means, and the setting that causes it (null: the model itself). */
  const SKIPS = {
    noSwing: ["Không có swing 15m đang chạy (ngoài nến 3 / nến 4)", null], against: ["Ngược hướng swing 15m", null],
    eq: ["Giá đóng sai phía EQ nến 2", null], broken: ["Swing đã hỏng (đóng qua đỉnh / đáy nến 2)", null], busy: ["Đang có lệnh khác", null],
    ideal: ["Không phải ideal formation", "entryIdeal"], monday: ["Thứ Hai", "entrySkipMonday"], killzone: ["Ngoài killzone", "entryKillzones"],
    profile: ["Hồ sơ ngày không cho phép", "entryDailyProfile"], bias: ["Ngược bias ngày", "entryDailyBias"], h1: ["Ngược bias nến H1", "entryAlignH1"],
    discount: ["Không ở discount / premium", "entryDiscount"], strong: ["Nến CISD yếu", "entryStrong"], news: ["Giờ ra tin", "entryNews"],
    perSwing: ["Swing đã có lệnh", "entryOnePerSwing"], unfilled: ["Limit không khớp", "entryMode"], target: ["Mục tiêu quá gần (dưới 1R)", "entryTarget"], risk: ["SL quá gần (< 0.8) hoặc quá xa", null],
  };

  /** Win rate, R and drawdown of a list of trades. */
  function stats(trades) {
    const closed = trades.filter((t) => t.why !== "open");
    const wins = closed.filter((t) => t.r > 0), losses = closed.filter((t) => t.r <= 0);
    let eq = 0, peak = 0, dd = 0, streak = 0, worst = 0;
    closed.forEach((t) => {
      eq += t.r; peak = Math.max(peak, eq); dd = Math.max(dd, peak - eq);
      streak = t.r <= 0 ? streak + 1 : 0; worst = Math.max(worst, streak);
    });
    const gain = wins.reduce((a, t) => a + t.r, 0), loss = -losses.reduce((a, t) => a + t.r, 0);
    return { trades: closed.length, wins: wins.length, winRate: closed.length ? wins.length / closed.length : 0, totalR: eq,
      avgR: closed.length ? eq / closed.length : 0, profitFactor: loss ? gain / loss : null, maxDD: dd, worstStreak: worst };
  }

  /* ----- everything ----- */

  function compute(bars, sec, cfg, ctx = {}) {
    if (!bars || bars.length < 20) return null;
    const fmt = ctx.fmt || ((v) => v.toFixed(2));
    const htfSec = pairOf(sec, cfg.htf);
    const out = { sec, htfSec, htfName: HTF_NAMES[htfSec] || `${htfSec / 60}m`, htf: null, cisd: [], breakers: [], notes: [] };
    if (htfSec > sec) {
      const h = aggregate(bars, sec, htfSec);
      if (h.length >= 3) out.htf = htfStory(h, fmt);
    }
    if (cfg.view === "setup") return setupView(bars, sec, htfSec, cfg, ctx, out, fmt);
    if (cfg.cisd) {
      const levels = String(cfg.projLevels).split(",").map((v) => +v).filter((v) => isFinite(v) && v !== 0);
      const poi = [];
      if (out.htf && out.htf.pch) { poi.push(out.htf.pch.high, out.htf.pch.low); }
      if (out.htf && out.htf.swing) poi.push(out.htf.swing.c1.high, out.htf.swing.c1.low);
      out.cisd = cisds(bars, levels, poi, cfg.cisdPoiOnly).slice(-Math.max(1, cfg.cisdCount));
    }
    if (cfg.breakers) out.breakers = breakers(bars, cfg.unicorn).slice(-Math.max(1, cfg.breakerCount));
    if (cfg.rules) out.notes = rules(bars[bars.length - 1].time, ctx.events);
    if (cfg.entries && sec === 60) {
      try { out.entries = botEntries(bars, cfg).slice(-40); } catch { out.entries = []; }
    }
    // The lines of the panel.
    const lines = [];
    const sw = out.htf && out.htf.swing;
    if (sw) lines.push({ text: `${out.htfName}: swing ${sw.dir > 0 ? "ĐÁY" : "ĐỈNH"} (${sw.kind === "c2" ? "nến 2 đóng lại trong nến 1" : "nến 3 đóng mạnh"}) — ${sw.state}`, dir: sw.broken ? 0 : sw.dir });
    else if (out.htf) lines.push({ text: `${out.htfName}: chưa có swing nến 2 / nến 3 → chờ`, dir: 0 });
    if (out.htf && out.htf.bias) lines.push({ text: `Bias ${out.htfName}: ${out.htf.bias.why}`, dir: out.htf.bias.dir });
    // The projection: the newest CISD in the direction of the higher timeframe swing (else the newest one).
    const want = sw && !sw.broken ? sw.dir : 0;
    let pick = out.cisd.length - 1;
    for (let k = out.cisd.length - 1; k >= 0; k--) if (!want || out.cisd[k].dir === want) { pick = k; break; }
    out.projIdx = pick;
    const last = out.cisd[pick];
    if (last) {
      const t = last.proj.map((p) => `${p.k} ${fmt(p.price)}`).join(" · ");
      lines.push({ text: `CISD ${last.dir > 0 ? "TĂNG" : "GIẢM"} ${fmt(last.level)}${last.poi ? " (tại POI)" : ""} → mục tiêu ${t}`, dir: last.dir });
    }
    const live = (out.entries || []).filter((t) => t.why === "open").pop();
    if (live) lines.push({ text: `TÍN HIỆU ${live.dir > 0 ? "MUA" : "BÁN"} M1${live.model && live.model !== "A" ? " (" + BOT_MODELS[live.model] + ")" : ""} · vào ${fmt(live.entry)} · SL ${fmt(live.stop)} · TP ${fmt(live.target)}`, dir: live.dir });
    out.notes.forEach((t) => lines.push({ text: "⚠ " + t, dir: 0, warn: true }));
    out.lines = lines;
    return out;
  }

  const hhmm = (t) => new Date(t * 1000).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" });
  const TF_LABEL = (sec) => (sec < 60 ? `${sec}s` : sec < 3600 ? `${sec / 60}m` : sec < 86400 ? `H${sec / 3600}` : "D1");

  /** The clean view: fixed setups and a short card about the newest one. */
  function setupView(bars, sec, htfSec, cfg, ctx, out, fmt) {
    out.view = "setup";
    out.lastIdx = bars.length - 1;
    out.setups = setupTimeline(bars, sec, htfSec, cfg);
    if (cfg.rules) out.notes = rules(bars[bars.length - 1].time, ctx.events);
    // The setup the card is about: the newest one still running, else the newest.
    const running = out.setups.filter((x) => x.status === "wait" || x.status === "signal" || x.status === "open");
    const su = running[running.length - 1] || out.setups[out.setups.length - 1];
    out.focus = su || null;
    const lines = [], tf = TF_LABEL(sec);
    const side = (d) => (d > 0 ? "MUA" : "BÁN");
    if (!su) lines.push({ text: `${out.htfName}: chưa có setup (chờ nến 2 quét nến 1 rồi đóng lại)`, dir: 0 });
    else {
      const how = su.kind === "c2" ? `nến 2 quét ${su.dir > 0 ? "đáy" : "đỉnh"} nến 1 (${fmt(su.swept)}) rồi đóng lại` : `nến 3 đóng mạnh qua nến 2`;
      lines.push({ text: `Setup #${su.n} ${side(su.dir)} · ${out.htfName}: ${how}`, dir: su.dir });
      const t = su.trade;
      if (su.status === "wait" && su.blocked) lines.push({ text: `Chưa được vào lệnh: ${su.blocked}${su.blocked === "ngoài killzone" ? " (killzone 2–5h, 7–10h giờ New York)" : ""} · chỉ vào khi có CISD ${su.dir > 0 ? "tăng" : "giảm"} hợp lệ`, dir: 0 });
      else if (su.status === "wait") lines.push({ text: `Chờ CISD ${su.dir > 0 ? "tăng" : "giảm"} trên ${tf} đến ${hhmm(su.endTime)} · giữ ${su.dir > 0 ? "trên" : "dưới"} EQ ${fmt(su.eq)} · huỷ nếu đóng ${su.dir > 0 ? "dưới" : "trên"} ${fmt(su.invalid)}`, dir: 0 });
      else if (su.status === "signal") lines.push({ text: `CISD vừa xác nhận → ${side(su.dir)} ở giá mở nến kế tiếp · SL ${fmt(t.stop)}`, dir: su.dir });
      else if (su.status === "open") lines.push({ text: `ĐANG ${side(su.dir)} ${fmt(t.entry)} · SL ${fmt(t.stop)} · TP ${fmt(t.target)}`, dir: su.dir });
      else if (t) lines.push({ text: `Đã xong: ${side(su.dir)} ${fmt(t.entry)} → ${t.r >= 0 ? "+" : ""}${t.r.toFixed(1)}R (${SETUP_STATUS[su.status]})`, dir: t.r > 0 ? 1 : -1 });
      else if (su.status === "broken") lines.push({ text: `Đã huỷ: có nến đóng ${su.dir > 0 ? "dưới" : "trên"} ${fmt(su.invalid)} → chờ setup mới`, dir: 0 });
      else lines.push({ text: `Hết giờ, không có CISD hợp lệ → chờ setup mới`, dir: 0 });
      const sk = su.skips[su.skips.length - 1];
      if (sk && !t) lines.push({ text: `CISD ${hhmm(bars[Math.min(sk.at, bars.length - 1)].time)} bị bỏ: ${sk.why}`, dir: 0 });
      // The checklist of the documents for this setup: what holds (✓), what does not (✗), * = required.
      if (su.list) {
        const min = cfg.setupMode === "score" ? +cfg.setupMinScore || 0 : 0, ok = su.score;
        const mustMiss = su.list.filter((x) => x.must && !x.ok && !x.later);
        const verdict = t && t.entry != null ? "đã đủ → có lệnh" : su.status === "signal" ? "ĐỦ → vào lệnh ở nến kế tiếp"
          : mustMiss.length ? `thiếu bắt buộc: ${mustMiss.map((x) => CHECK_NAMES[x.k]).join(", ")}` : ok >= min ? "đủ điểm → chờ CISD" : `cần thêm ${min - ok} điểm`;
        lines.push({ text: `Checklist ${ok}/${su.list.length} (cần ${min}, * bắt buộc): ${verdict}`, dir: t && t.entry != null || su.status === "signal" ? su.dir : 0 });
        lines.push({ items: su.list.map((x) => ({ text: (x.must ? "*" : "") + CHECK_NAMES[x.k] + (x.k === "zone" ? (su.dir > 0 ? " discount" : " premium") : ""), ok: x.ok, later: x.later && !x.ok })) });
      }
    }
    // The record of these rules on the bars loaded: every setup that traded, wins and losses.
    const done = out.setups.filter((x) => x.trade && x.trade.r != null && x.status !== "open");
    if (done.length) {
      const w = done.filter((x) => x.trade.r > 0).length, R = done.reduce((a, x) => a + x.trade.r, 0);
      lines.push({ text: `Trên chart (${out.setups.length} setup): ${done.length} lệnh · ${w} thắng / ${done.length - w} thua (${Math.round((w / done.length) * 100)}%) · ${R >= 0 ? "+" : ""}${R.toFixed(1)}R`, dir: R > 0 ? 1 : R < 0 ? -1 : 0 });
    }
    // Honest notes from the backtests (gold, April to November 2026): the model alone has no edge.
    if (!(sec === 60 && htfSec === 900)) out.notes.unshift(`Cặp ${tf}→${out.htfName}: backtest vàng 7 tháng thua lỗ (~40% thắng) — chỉ để tham khảo, nên dùng 1m→15m`);
    else if (cfg.setupMode === "score") {
      const m = String(cfg.setupMust || "").split(",");
      const off = [!m.includes("kz") && "killzone", !m.includes("profile") && "hồ sơ ngày"].filter(Boolean);
      if (off.length) out.notes.unshift(`Không bắt buộc ${off.join(", ")}: backtest vàng thua lỗ (~40–46% thắng)`);
    } else {
      const off = [!cfg.entryKillzones && "killzone", !cfg.entryDailyProfile && "hồ sơ ngày", !cfg.entryDiscount && "discount"].filter(Boolean);
      if (off.length) out.notes.unshift(`Đang tắt bộ lọc ${off.join(", ")}: không có bộ lọc, mô hình chỉ ~40% thắng và lỗ sau phí`);
    }
    out.notes.forEach((t) => lines.push({ text: "⚠ " + t, dir: 0, warn: true }));
    out.lines = lines;
    return out;
  }

  /* ----- drawing ----- */

  const FONT = "600 10.5px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";

  function rgba(hex, a) {
    const h = (hex || "#787b86").replace("#", "");
    return `rgba(${parseInt(h.slice(0, 2), 16)}, ${parseInt(h.slice(2, 4), 16)}, ${parseInt(h.slice(4, 6), 16)}, ${a})`;
  }

  function draw(g, o, cfg, X, Y, w, h, fmt) {
    if (!o) return;
    fmt = fmt || ((v) => v.toFixed(2));
    g.save();
    g.font = FONT;
    g.textBaseline = "middle";
    const hline = (price, x0, x1, color, dash, label, align = "right") => {
      const y = Y(price);
      if (y == null) return;
      const yy = Math.round(y) + 0.5;
      g.strokeStyle = color; g.lineWidth = 1; g.setLineDash(dash || []);
      g.beginPath(); g.moveTo(Math.max(0, x0), yy); g.lineTo(Math.min(w, x1), yy); g.stroke();
      g.setLineDash([]);
      if (label) {
        g.fillStyle = color; g.textAlign = align === "left" ? "left" : "right";
        g.fillText(label, align === "left" ? Math.max(2, x0) + 4 : Math.min(w, x1) - 4, yy - 7);
      }
    };
    const xi = (i) => X(i);
    if (o.view === "setup") { drawSetups(g, o, cfg, X, Y, w, fmt, hline); g.restore(); return; }

    // Breakers and unicorns (under the rest).
    (o.breakers || []).forEach((b) => {
      const x0 = xi(b.from), x1 = b.to != null ? xi(b.to) : w;
      const y0 = Y(b.top), y1 = Y(b.bottom);
      if (x0 == null || x1 == null || y0 == null || y1 == null || x1 < 0) return;
      const left = Math.max(0, x0);
      g.fillStyle = rgba(cfg.breakerColor, b.to != null ? 0.08 : 0.16);
      g.fillRect(left, Math.min(y0, y1), Math.max(1, x1 - left), Math.abs(y1 - y0));
      g.strokeStyle = rgba(b.dir > 0 ? cfg.bull : cfg.bear, 0.7); g.lineWidth = 1; g.setLineDash([4, 3]);
      g.strokeRect(Math.round(left) + 0.5, Math.round(Math.min(y0, y1)) + 0.5, Math.round(Math.max(1, x1 - left)), Math.round(Math.abs(y1 - y0)));
      g.setLineDash([]);
      g.fillStyle = b.dir > 0 ? cfg.bull : cfg.bear; g.textAlign = "left";
      g.fillText(b.dir > 0 ? "BB tăng" : "BB giảm", left + 4, Math.min(y0, y1) + 8);
      if (b.unicorn) {
        const u0 = Y(b.unicorn.top), u1 = Y(b.unicorn.bottom), ux = xi(b.unicorn.at);
        if (u0 != null && u1 != null && ux != null) {
          g.fillStyle = rgba(cfg.unicornColor, 0.28);
          g.fillRect(Math.max(0, ux), Math.min(u0, u1), Math.max(1, x1 - Math.max(0, ux)), Math.max(1, Math.abs(u1 - u0)));
          g.fillStyle = cfg.unicornColor;
          g.fillText("🦄 Unicorn", Math.max(0, ux) + 4, Math.max(u0, u1) + 9);
        }
      }
    });

    // The higher timeframe: candles 1-4, the swept level, the equilibrium to hold, PCH / PCL.
    const s = o.htf && o.htf.swing;
    if (s && cfg.swing) {
      const color = s.broken ? "#787b86" : s.dir > 0 ? cfg.bull : cfg.bear;
      [s.c1, s.c2, s.c3, s.c4].forEach((c, k) => {
        if (!c) return;
        const xa = xi(c.start), xb = xi(c.end);
        if (xa == null || xb == null || xb < 0 || xa > w) return;
        const xm = (xa + xb) / 2, y = Y(s.dir > 0 ? c.low : c.high);
        if (y == null) return;
        // The candle's span on this chart: a light bracket, its number in a ring.
        g.strokeStyle = rgba(color, 0.55); g.lineWidth = 1;
        const yb = y + (s.dir > 0 ? 12 : -12);
        g.beginPath(); g.moveTo(xa, yb); g.lineTo(xb, yb); g.stroke();
        const yc = yb + (s.dir > 0 ? 11 : -11);
        g.fillStyle = k === 1 ? color : "rgba(21, 28, 42, 0.85)";
        g.beginPath(); g.arc(xm, yc, 8, 0, Math.PI * 2); g.fill();
        g.strokeStyle = color; g.stroke();
        g.fillStyle = k === 1 ? "#ffffff" : color; g.textAlign = "center";
        g.fillText(String(k + 1), xm, yc + 0.5);
      });
      const x2 = xi(s.c2.start);
      if (x2 != null) {
        hline(s.dir > 0 ? s.c1.low : s.c1.high, xi(s.c1.start), xi(s.c2.end) + 30, rgba(color, 0.8), [2, 3], s.dir > 0 ? "đáy nến 1 (bị quét)" : "đỉnh nến 1 (bị quét)", "left");
        if (cfg.eqLines) {
          hline(s.eq2.price, x2, w, cfg.eqColor, [6, 4], `${s.eq2.label} ${fmt(s.eq2.price)}`);
          if (s.eq3 && s.c3) hline(s.eq3.price, xi(s.c3.start), w, cfg.eqColor, [2, 3], `${s.eq3.label} ${fmt(s.eq3.price)}`);
        }
        hline(s.target, x2, w, rgba(color, 0.9), [], `mục tiêu ${s.dir > 0 ? "đỉnh" : "đáy"} nến 1 ${fmt(s.target)}`);
      }
    }
    if (o.htf && o.htf.pch && cfg.pcl) {
      const c = o.htf.pch, x0 = xi(c.start);
      if (x0 != null) {
        hline(c.high, x0, w, "rgba(120, 123, 134, 0.9)", [5, 4], `PCH ${o.htfName} ${fmt(c.high)}`);
        hline(c.low, x0, w, "rgba(120, 123, 134, 0.9)", [5, 4], `PCL ${o.htfName} ${fmt(c.low)}`);
      }
    }

    // CISD with its projections.
    (o.cisd || []).forEach((c, idx, all) => {
      const color = c.dir > 0 ? cfg.bull : cfg.bear;
      const x0 = xi(c.from), x1 = xi(c.at);
      if (x0 == null || x1 == null || x1 < 0) return;
      hline(c.level, x0, x1 + 4, color, [], "", "left");
      const y = Y(c.level);
      if (y != null) {
        g.fillStyle = color; g.textAlign = "left";
        g.fillText(`CISD${c.poi ? "" : "?"}`, Math.max(2, x0) + 2, y + (c.dir > 0 ? 9 : -8));
      }
      if (!cfg.projections || idx !== (o.projIdx != null ? o.projIdx : all.length - 1)) return;
      const xe = Math.min(w, x1 + 220);
      c.proj.forEach((p) => hline(p.price, x1, xe, rgba(cfg.projColor, 0.85), [3, 3], `${p.k}  ${fmt(p.price)}`));
      hline(c.dir > 0 ? c.hi : c.lo, x1, xe, rgba(cfg.projColor, 0.5), [], "0");
      hline(c.dir > 0 ? c.lo : c.hi, x1, xe, rgba(cfg.projColor, 0.5), [], "1");
    });

    // M1 entries: the trade as a small position box (target green, stop red), an arrow at the entry and the result.
    (o.entries || []).forEach((t) => {
      const x0 = xi(t.at), x1 = t.why === "open" ? w : xi(t.exitAt);
      const ye = Y(t.entry), ys = Y(t.stop), yt = Y(t.target);
      if (x0 == null || x1 == null || ye == null || ys == null || yt == null || x1 < 0 || x0 > w) return;
      const left = Math.max(0, x0), width = Math.max(3, x1 - left);
      g.fillStyle = rgba(cfg.bull, 0.13); g.fillRect(left, Math.min(ye, yt), width, Math.abs(yt - ye));
      g.fillStyle = rgba(cfg.bear, 0.13); g.fillRect(left, Math.min(ye, ys), width, Math.abs(ys - ye));
      g.strokeStyle = t.dir > 0 ? cfg.bull : cfg.bear; g.lineWidth = 1;
      g.beginPath(); g.moveTo(left, Math.round(ye) + 0.5); g.lineTo(left + width, Math.round(ye) + 0.5); g.stroke();
      // The arrow under a buy / over a sell.
      const ya = t.dir > 0 ? Math.max(ye, ys) + 10 : Math.min(ye, ys) - 10;
      g.fillStyle = t.dir > 0 ? cfg.bull : cfg.bear;
      g.beginPath();
      if (t.dir > 0) { g.moveTo(x0, ya - 6); g.lineTo(x0 - 5, ya + 3); g.lineTo(x0 + 5, ya + 3); }
      else { g.moveTo(x0, ya + 6); g.lineTo(x0 - 5, ya - 3); g.lineTo(x0 + 5, ya - 3); }
      g.closePath(); g.fill();
      const res = t.why === "open" ? "đang chạy" : `${t.r >= 0 ? "+" : ""}${t.r.toFixed(1)}R`;
      g.fillStyle = t.why === "open" ? "#f2c14e" : t.r > 0 ? cfg.bull : cfg.bear; g.textAlign = "left";
      g.fillText(`${t.dir > 0 ? "MUA" : "BÁN"} ${res}`, x0 + 7, ya + (t.dir > 0 ? 4 : -2));
    });

    g.restore();
  }

  /** The panel alone, drawn over the candles (the chart's top layer). */
  function drawPanelOnly(g, o, cfg, w, h) {
    if (!o) return;
    g.save(); g.textBaseline = "middle"; drawPanel(g, o, cfg, w, h); g.restore();
  }

  /** X of a fractional bar index (a window that runs past the last bar). */
  function xAt(X, i) {
    const a = Math.floor(i), xa = X(a);
    if (xa == null || i === a) return xa;
    const xb = X(a + 1);
    return xb == null ? xa : xa + (xb - xa) * (i - a);
  }

  const STATUS_COLOR = { wait: "#f2c14e", signal: "#f2c14e", open: "#2962ff", win: "#089981", loss: "#f23645", flat: "#787b86", broken: "#787b86", expired: "#787b86", skipped: "#787b86" };

  /** A small rounded tag. */
  function pill(g, text, x, y, bg, fg, align = "left") {
    const tw = g.measureText(text).width, pw = tw + 10, ph = 16;
    const x0 = align === "right" ? x - pw : align === "center" ? x - pw / 2 : x;
    g.fillStyle = bg; g.beginPath(); g.roundRect(x0, y - ph / 2, pw, ph, 4); g.fill();
    g.fillStyle = fg; g.textAlign = "left"; g.fillText(text, x0 + 5, y + 0.5);
    return pw;
  }

  /** The fixed setups: the swept level, the window with the levels that decide it (EQ to hold, the close that
   *  cancels it, candle 1's target), the trade as a position box with its labels, and the result. */
  function drawSetups(g, o, cfg, X, Y, w, fmt, hline) {
    // Swings form every few candles, so the chart keeps to: the setups still running and the newest one in
    // full, the last few that traded as their trade only, and (optional) the cancelled ones, faint.
    const all = o.setups || [], count = Math.max(1, cfg.setupCount || 4);
    const isDead = (s) => s.status === "broken" || s.status === "expired" || s.status === "skipped";
    const focus = o.focus;
    const full = all.filter((s) => s === focus || s.status === "wait" || s.status === "signal" || s.status === "open");
    const traded = all.filter((s) => s.trade && s.trade.entry != null && !full.includes(s)).slice(-count);
    const faint = cfg.setupDead ? all.filter((s) => isDead(s) && !full.includes(s)).slice(-count) : [];
    const list = [...faint, ...traded, ...full];
    list.forEach((s) => {
      const newest = s === focus;
      const brief = traded.includes(s);
      const dead = isDead(s);
      const color = dead ? "#787b86" : s.dir > 0 ? cfg.bull : cfg.bear;
      const x0 = X(s.from > o.lastIdx ? o.lastIdx : s.from), x1 = xAt(X, s.endIdx);
      const xc1 = X(s.c1.start), xc2 = X(s.c2.end);
      if (x0 == null || x1 == null || x1 < 0 || (xc1 != null && xc1 > w)) return;
      g.globalAlpha = dead && !newest ? 0.35 : dead ? 0.6 : 1;
      if (!brief) {
      // Candle 1 and 2 of the higher timeframe: numbered rings over / under them, the swept level.
      [[s.c1, 1], [s.c2, 2]].forEach(([c, k]) => {
        const xa = X(c.start), xb = X(c.end);
        if (xa == null || xb == null) return;
        const y = Y(s.dir > 0 ? c.low : c.high);
        if (y == null) return;
        const yc = y + (s.dir > 0 ? 16 : -16), xm = (xa + xb) / 2;
        g.fillStyle = k === 2 ? color : "rgba(21, 28, 42, 0.85)";
        g.beginPath(); g.arc(xm, yc, 7, 0, Math.PI * 2); g.fill();
        g.strokeStyle = color; g.lineWidth = 1; g.stroke();
        g.fillStyle = k === 2 ? "#ffffff" : color; g.textAlign = "center"; g.fillText(String(k), xm, yc + 0.5);
      });
      if (xc1 != null && xc2 != null) hline(s.swept, xc1, xc2 + 6, rgba(color, 0.8), [2, 3], "");
      // The window: a light band between the cancel level and the target, with the levels.
      const yi = Y(s.invalid), yt = Y(s.target);
      if (yi != null && yt != null) {
        g.fillStyle = rgba(color, newest && !dead ? 0.06 : 0.035);
        g.fillRect(Math.max(0, x0), Math.min(yi, yt), Math.max(2, x1 - Math.max(0, x0)), Math.abs(yt - yi));
      }
      const xl = Math.max(2, x0);
      hline(s.invalid, x0, x1, rgba(cfg.bear === color ? "#ff9800" : cfg.bear, 0.9), [5, 3], newest ? `Huỷ nếu đóng ${s.dir > 0 ? "dưới" : "trên"} ${fmt(s.invalid)}` : "", "left");
      if (cfg.eqLines) hline(s.eq, x0, x1, cfg.eqColor, [6, 4], newest ? `${s.eqLabel} ${fmt(s.eq)}` : "", "left");
      hline(s.target, x0, x1, rgba(color, 0.9), [], newest ? `Mục tiêu nến 1 ${fmt(s.target)}` : "", "left");
      // The header: number, side, status.
      const yh = Y(s.dir > 0 ? Math.min(s.invalid, s.target) : Math.max(s.invalid, s.target));
      const label = s.status === "wait" && s.blocked ? `chưa vào: ${s.blocked}` : SETUP_STATUS[s.status];
      if (yh != null) pill(g, `#${s.n} ${s.dir > 0 ? "MUA" : "BÁN"} · ${label}`, xl, yh + (s.dir > 0 ? 14 : -24), rgba(s.status === "wait" && s.blocked ? "#787b86" : STATUS_COLOR[s.status], 0.9), "#ffffff");
      // The CISD that was skipped (newest setup only): a small cross with the reason.
      if (cfg.setupSkips && newest && !s.trade) s.skips.slice(-3).forEach((k) => {
        const xx = X(k.at), yy = Y(k.level);
        if (xx == null || yy == null) return;
        g.strokeStyle = "#9aa4b2"; g.lineWidth = 1.5;
        g.beginPath(); g.moveTo(xx - 4, yy - 4); g.lineTo(xx + 4, yy + 4); g.moveTo(xx + 4, yy - 4); g.lineTo(xx - 4, yy + 4); g.stroke();
        g.fillStyle = "#9aa4b2"; g.textAlign = "left"; g.fillText(k.why, xx + 7, yy + (s.dir > 0 ? 10 : -10));
      });
      }
      g.globalAlpha = 1;
      const t = s.trade;
      if (!t) return;
      // The CISD that triggered it.
      const xf = X(t.cisd.from), xa = X(t.cisd.at);
      if (xf != null && xa != null) {
        hline(t.cisd.level, xf, xa + 4, color, [], "", "left");
        const yy = Y(t.cisd.level);
        if (yy != null) { g.fillStyle = color; g.textAlign = "left"; g.fillText("CISD", Math.max(2, xf) + 2, yy + (s.dir > 0 ? 9 : -8)); }
      }
      if (t.entry == null) return;
      // The trade: a position box (target green, stop red) from the entry to the exit.
      const xe = X(t.at), xx = t.why === "open" ? Math.max(x1, X(o.lastIdx) + 40) : X(t.exitAt);
      const ye = Y(t.entry), ys = Y(t.stop), yt2 = Y(t.target);
      if (xe == null || xx == null || ye == null || ys == null || yt2 == null) return;
      const left = Math.max(0, xe), width = Math.max(24, xx - left);
      g.fillStyle = rgba(cfg.bull, 0.16); g.fillRect(left, Math.min(ye, yt2), width, Math.abs(yt2 - ye));
      g.fillStyle = rgba(cfg.bear, 0.16); g.fillRect(left, Math.min(ye, ys), width, Math.abs(ys - ye));
      g.strokeStyle = s.dir > 0 ? cfg.bull : cfg.bear; g.lineWidth = 1.5;
      g.beginPath(); g.moveTo(left, Math.round(ye) + 0.5); g.lineTo(left + width, Math.round(ye) + 0.5); g.stroke();
      // Labels on the box's right side: entry, stop, target.
      // Labels right of the box: "#n BÁN entry · result", the stop and the target (kept apart when close).
      const lx = left + width + 4;
      const res = t.why === "open" ? " · đang chạy" : ` · ${t.r >= 0 ? "+" : ""}${t.r.toFixed(1)}R ${t.r > 0 ? "✓" : "✗"}`;
      pill(g, `#${s.n} ${s.dir > 0 ? "MUA" : "BÁN"} ${fmt(t.entry)}${s.score != null ? ` · ${s.score}/${s.list.length}` : ""}${res}`, lx, ye, t.why === "open" ? (s.dir > 0 ? cfg.bull : cfg.bear) : t.r > 0 ? cfg.bull : cfg.bear, "#ffffff");
      const gap = (y) => (Math.abs(y - ye) < 17 ? ye + Math.sign(y - ye || 1) * 17 : y);
      pill(g, `SL ${fmt(t.stop)}`, lx, gap(ys), "rgba(242, 54, 69, 0.85)", "#ffffff");
      pill(g, `TP ${fmt(t.target)}`, lx, gap(yt2), "rgba(8, 153, 129, 0.85)", "#ffffff");
    });
  }

  /** The panel: the story in a few lines, bottom left. */
  function drawPanel(g, o, cfg, w, h) {
    if (!cfg.panel || !o.lines || !o.lines.length) return;
    g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
    const lh = 17, pad = 8, maxW = Math.min(w - 20, 560), inner = maxW - pad * 2 - 10;
    // Rows: a text line, or chips (the checklist) wrapped onto as many rows as they need.
    const rows = [];
    o.lines.forEach((l) => {
      if (!l.items) { rows.push({ l, text: fit(g, l.text, inner) }); return; }
      let row = [], x = 0;
      l.items.forEach((it) => {
        const cw = g.measureText(`✓ ${it.text}`).width + 12;
        if (row.length && x + cw > inner) { rows.push({ chips: row, width: x }); row = []; x = 0; }
        row.push({ it, x, cw }); x += cw + 4;
      });
      if (row.length) rows.push({ chips: row, width: x });
    });
    const bw = Math.min(maxW, Math.max(...rows.map((r) => (r.chips ? r.width : g.measureText(r.text).width))) + pad * 2 + 10);
    const bh = rows.length * lh + pad * 2 - 4, bx = 10, by = h - bh - 44;
    g.fillStyle = "rgba(15, 20, 30, 0.94)";
    g.beginPath(); g.roundRect(bx, by, bw, bh, 8); g.fill();
    rows.forEach((r, i) => {
      const yy = by + pad + i * lh + 6;
      if (r.chips) {
        r.chips.forEach(({ it, x, cw }) => {
          const c = it.ok ? cfg.bull : it.later ? "#787b86" : cfg.bear;
          g.fillStyle = rgba(c, 0.22); g.beginPath(); g.roundRect(bx + pad + 12 + x, yy - 7, cw, 14, 4); g.fill();
          g.fillStyle = it.ok ? "#9ff0d6" : it.later ? "#b2b5be" : "#ffb3ba"; g.textAlign = "left";
          g.fillText(`${it.ok ? "✓" : it.later ? "…" : "✗"} ${it.text}`, bx + pad + 18 + x, yy + 0.5);
        });
        return;
      }
      g.fillStyle = r.l.warn ? "#f5a524" : r.l.dir > 0 ? cfg.bull : r.l.dir < 0 ? cfg.bear : "#c9d1dc";
      g.beginPath(); g.arc(bx + pad + 3, yy, 3, 0, Math.PI * 2); g.fill();
      g.fillStyle = "#e8ecf3"; g.textAlign = "left";
      g.fillText(r.text, bx + pad + 12, yy + 0.5);
    });
  }

  function fit(g, text, max) {
    if (g.measureText(text).width <= max) return text;
    let t = text;
    while (t.length > 10 && g.measureText(t + "…").width > max) t = t.slice(0, -1);
    return t + "…";
  }

  window.MODELS = { defaults, merge, compute, draw, drawPanelOnly, pairOf, aggregate, cisds, breakers, htfStory, HTF_NAMES, entries, setupTimeline, SETUP_STATUS, CHECK_NAMES, CHECK_LABELS, liquidityEntries, dailyBot, botEntries, BOT_MODELS, entryDefaults, entryOptions, stats, SKIPS, nyClock };
})();
