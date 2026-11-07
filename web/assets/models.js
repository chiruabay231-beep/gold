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
      htf: "auto", swing: true, eqLines: true, pcl: true, cisd: true, cisdPoiOnly: true, cisdCount: 3,
      projections: true, projLevels: "-1,-2,-2.5,-4", breakers: true, breakerCount: 3, unicorn: true, rules: true, panel: true,
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
        const poi = sweptAbove(bars, piv.highs, hi, 60) || poiLevels.some((p) => bars[hi].high > p && Math.min(bars[up.start].low, bars[lo].low) < p);
        if (!onlyPoi || poi) out.push(projected(-1, up.level, up.start, i, bars[hi].high, bars[lo].low, hi, poi, levels));
      }
      if (down && !down.used && i > down.end && b.close > down.level) {
        down.used = true;
        let lo = down.start;
        for (let k = down.start; k <= i; k++) if (bars[k].low < bars[lo].low) lo = k;
        let hi = down.start;
        for (let k = Math.max(0, down.start - 3); k <= lo; k++) if (bars[k].high > bars[hi].high) hi = k;
        const poi = sweptBelow(bars, piv.lows, lo, 60) || poiLevels.some((p) => bars[lo].low < p && Math.max(bars[down.start].high, bars[hi].high) > p);
        if (!onlyPoi || poi) out.push(projected(1, down.level, down.start, i, bars[hi].high, bars[lo].low, lo, poi, levels));
      }
    }
    return out;
  }

  /** The extreme at `at` took a pivot high / low formed before it (within `look` bars). */
  function sweptAbove(bars, highs, at, look) {
    return highs.some((p) => p < at - 1 && p >= at - look && bars[at].high > bars[p].high);
  }
  function sweptBelow(bars, lows, at, look) {
    return lows.some((p) => p < at - 1 && p >= at - look && bars[at].low < bars[p].low);
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
    if (cfg.cisd) {
      const levels = String(cfg.projLevels).split(",").map((v) => +v).filter((v) => isFinite(v) && v !== 0);
      const poi = [];
      if (out.htf && out.htf.pch) { poi.push(out.htf.pch.high, out.htf.pch.low); }
      if (out.htf && out.htf.swing) poi.push(out.htf.swing.c1.high, out.htf.swing.c1.low);
      out.cisd = cisds(bars, levels, poi, cfg.cisdPoiOnly).slice(-Math.max(1, cfg.cisdCount));
    }
    if (cfg.breakers) out.breakers = breakers(bars, cfg.unicorn).slice(-Math.max(1, cfg.breakerCount));
    if (cfg.rules) out.notes = rules(bars[bars.length - 1].time, ctx.events);
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

    // The panel: the story in a few lines, bottom left.
    if (cfg.panel && o.lines && o.lines.length) {
      g.font = "600 11px -apple-system, BlinkMacSystemFont, 'Trebuchet MS', Roboto, Ubuntu, sans-serif";
      const lh = 17, pad = 8, maxW = Math.min(w - 20, 560);
      const rows = o.lines.map((l) => ({ l, text: fit(g, l.text, maxW - pad * 2 - 10) }));
      const bw = Math.min(maxW, Math.max(...rows.map((r) => g.measureText(r.text).width)) + pad * 2 + 10);
      const bh = rows.length * lh + pad * 2 - 4, bx = 10, by = h - bh - 44;
      g.fillStyle = "rgba(15, 20, 30, 0.82)";
      g.beginPath(); g.roundRect(bx, by, bw, bh, 8); g.fill();
      rows.forEach((r, i) => {
        const yy = by + pad + i * lh + 6;
        g.fillStyle = r.l.warn ? "#f5a524" : r.l.dir > 0 ? cfg.bull : r.l.dir < 0 ? cfg.bear : "#c9d1dc";
        g.beginPath(); g.arc(bx + pad + 3, yy, 3, 0, Math.PI * 2); g.fill();
        g.fillStyle = "#e8ecf3"; g.textAlign = "left";
        g.fillText(r.text, bx + pad + 12, yy + 0.5);
      });
    }
    g.restore();
  }

  function fit(g, text, max) {
    if (g.measureText(text).width <= max) return text;
    let t = text;
    while (t.length > 10 && g.measureText(t + "…").width > max) t = t.slice(0, -1);
    return t + "…";
  }

  window.MODELS = { defaults, merge, compute, draw, pairOf, aggregate, cisds, breakers, htfStory, HTF_NAMES };
})();
